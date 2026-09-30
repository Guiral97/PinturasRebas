-- =====================================================================
--  02: Cartera y créditos
--  Ejecutar en Supabase > SQL Editor DESPUÉS de 01_esquema_pinturas.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Cupo y plazo por cliente
-- ---------------------------------------------------------------------
alter table public.clientes
  add column cupo_credito numeric(12,2) check (cupo_credito >= 0),   -- null = sin límite definido
  add column plazo_dias   integer not null default 30 check (plazo_dias >= 0);


-- ---------------------------------------------------------------------
-- 2. Abonos: cada pago que un cliente hace sobre una venta a crédito
-- ---------------------------------------------------------------------
create table public.abonos (
  id           bigint generated always as identity primary key,
  venta_id     bigint not null references public.ventas(id),
  cliente_id   bigint not null references public.clientes(id),
  valor        numeric(12,2) not null check (valor > 0),
  metodo_pago  text not null check (metodo_pago in ('efectivo', 'transferencia', 'tarjeta')),
  referencia   text,          -- número de transferencia, recibo, etc.
  nota         text,
  usuario_id   uuid references auth.users(id),
  creado_en    timestamptz not null default now()
);

create index on public.abonos (venta_id);
create index on public.abonos (cliente_id);

alter table public.abonos enable row level security;
create policy "usuarios activos consultan" on public.abonos
  for select to authenticated using (public.es_usuario_activo());


-- ---------------------------------------------------------------------
-- 3. Vistas de cartera (fechas en hora de Colombia)
-- ---------------------------------------------------------------------
create view public.v_cartera_ventas with (security_invoker = true) as
select
  v.id,
  v.cliente_id,
  c.nombre                                               as cliente,
  v.creado_en,
  (v.creado_en at time zone 'America/Bogota')::date      as fecha,
  v.total,
  coalesce(a.abonado, 0)                                 as abonado,
  v.total - coalesce(a.abonado, 0)                       as saldo,
  (v.creado_en at time zone 'America/Bogota')::date + c.plazo_dias as vence_en,
  greatest(
    (now() at time zone 'America/Bogota')::date
      - ((v.creado_en at time zone 'America/Bogota')::date + c.plazo_dias),
    0)                                                   as dias_vencida,
  v.estado
from public.ventas v
join public.clientes c on c.id = v.cliente_id
left join (
  select venta_id, sum(valor) as abonado from public.abonos group by venta_id
) a on a.venta_id = v.id
where v.metodo_pago = 'credito'
  and v.estado <> 'anulada';

create view public.v_cartera_clientes with (security_invoker = true) as
select
  c.id                                                   as cliente_id,
  c.nombre,
  c.documento,
  c.telefono,
  c.cupo_credito,
  c.plazo_dias,
  sum(cv.saldo)                                          as saldo,
  coalesce(sum(cv.saldo) filter (where cv.dias_vencida > 0), 0) as saldo_vencido,
  count(*)                                               as facturas_pendientes,
  min(cv.fecha)                                          as pendiente_desde,
  max(cv.dias_vencida)                                   as max_dias_vencida
from public.v_cartera_ventas cv
join public.clientes c on c.id = cv.cliente_id
where cv.saldo > 0
group by c.id;


-- ---------------------------------------------------------------------
-- 4. Reglas sobre ventas (trigger)
--    - No se puede anular una venta que ya tiene abonos.
--    - Una venta a crédito no puede superar el cupo del cliente.
--    registrar_venta crea la venta con total 0 y luego la actualiza,
--    así que la validación del cupo ocurre en ese UPDATE.
-- ---------------------------------------------------------------------
create or replace function public.validar_venta()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_cupo   numeric;
  v_saldo  numeric;
begin
  if new.estado = 'anulada' and old.estado <> 'anulada'
     and exists (select 1 from abonos where venta_id = new.id) then
    raise exception 'La venta % tiene abonos registrados y no se puede anular', new.id;
  end if;

  if new.metodo_pago = 'credito' and new.estado = 'pendiente_pago' and new.total > old.total then
    select cupo_credito into v_cupo from clientes where id = new.cliente_id;
    if v_cupo is not null then
      select coalesce(sum(saldo), 0) into v_saldo
        from v_cartera_ventas
       where cliente_id = new.cliente_id and id <> new.id;
      if v_saldo + new.total > v_cupo then
        raise exception 'La venta supera el cupo de crédito del cliente. Cupo: %, saldo actual: %, esta venta: %',
          round(v_cupo), round(v_saldo), round(new.total);
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_validar_venta
  before update on public.ventas
  for each row execute function public.validar_venta();


-- ---------------------------------------------------------------------
-- 5. Registrar abono
--    Sin p_venta_id: reparte el valor desde la factura más antigua.
--    Con p_venta_id: lo aplica solo a esa venta.
--    Las facturas que quedan en cero pasan a 'pagada'.
-- ---------------------------------------------------------------------
create or replace function public.registrar_abono(
  p_cliente_id   bigint,
  p_valor        numeric,
  p_metodo_pago  text,
  p_venta_id     bigint default null,
  p_referencia   text   default null,
  p_nota         text   default null
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_restante     numeric := p_valor;
  v_saldo_total  numeric;
  v_venta        record;
  v_aplicar      numeric;
  v_abonadas     int := 0;
  v_saldadas     int := 0;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'El valor del abono debe ser mayor que cero';
  end if;
  if p_metodo_pago not in ('efectivo', 'transferencia', 'tarjeta') then
    raise exception 'Forma de pago no válida para un abono';
  end if;

  -- Bloquea las ventas pendientes del cliente mientras se aplica el abono
  perform 1 from ventas
   where cliente_id = p_cliente_id
     and estado = 'pendiente_pago'
     and (p_venta_id is null or id = p_venta_id)
   order by id
   for update;

  select coalesce(sum(saldo), 0) into v_saldo_total
    from v_cartera_ventas
   where cliente_id = p_cliente_id and saldo > 0
     and (p_venta_id is null or id = p_venta_id);

  if v_saldo_total = 0 then
    raise exception 'No hay saldo pendiente donde aplicar el abono';
  end if;
  if p_valor > v_saldo_total then
    raise exception 'El abono (%) supera el saldo pendiente (%)', round(p_valor), round(v_saldo_total);
  end if;

  for v_venta in
    select id, saldo from v_cartera_ventas
     where cliente_id = p_cliente_id and saldo > 0
       and (p_venta_id is null or id = p_venta_id)
     order by creado_en, id
  loop
    exit when v_restante <= 0;
    v_aplicar := least(v_restante, v_venta.saldo);

    insert into abonos (venta_id, cliente_id, valor, metodo_pago, referencia, nota, usuario_id)
    values (v_venta.id, p_cliente_id, v_aplicar, p_metodo_pago, p_referencia, p_nota, auth.uid());
    v_abonadas := v_abonadas + 1;

    if v_aplicar = v_venta.saldo then
      update ventas set estado = 'pagada' where id = v_venta.id;
      v_saldadas := v_saldadas + 1;
    end if;

    v_restante := v_restante - v_aplicar;
  end loop;

  return jsonb_build_object(
    'facturas_abonadas', v_abonadas,
    'facturas_saldadas', v_saldadas,
    'saldo_restante',    v_saldo_total - p_valor
  );
end;
$$;

revoke execute on function public.registrar_abono(bigint, numeric, text, bigint, text, text) from public, anon;
grant  execute on function public.registrar_abono(bigint, numeric, text, bigint, text, text) to authenticated;
revoke execute on function public.validar_venta() from public, anon;
