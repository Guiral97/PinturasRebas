-- =====================================================================
-- 18_devoluciones.sql — Devolución de una venta, completa o de algunas
-- unidades, sin anularla.
-- Se ejecuta después de 17_traslados_caja.sql (necesita 02, 11, 13, 14 y 17).
--
-- Qué hace:
--   1. devoluciones y devolucion_detalle: qué se devolvió de qué venta, por
--      cuánto, si cada línea vuelve al inventario (sellado) o no (dañado,
--      abierto) y cómo se le devolvió el dinero al cliente.
--   2. registrar_devolucion(p_venta_id, p_items, p_forma, p_motivo): cualquier
--      usuario activo. El valor sale de la venta (precio cobrado con el
--      descuento o recargo repartido), nunca del navegador. En una venta a
--      crédito primero baja la deuda; si el cliente ya había pagado, el resto
--      se le devuelve en efectivo o por transferencia.
--   3. anular_devolucion(p_id, p_motivo): solo socios. Saca otra vez del
--      inventario lo que había vuelto (movimiento 'devolucion' en negativo,
--      con nota) y la deuda regresa.
--   4. Una venta con devoluciones vigentes no se puede anular (la mercancía
--      volvería dos veces al inventario).
--   5. v_devoluciones: para el Tablero (valor, reembolso y costo de lo que
--      volvió al inventario).
--   6. Cartera: la devolución baja el saldo de la venta.
--   7. Cierre de caja: la devolución en efectivo resta de lo que debería haber.
--
-- Reemplaza:
--   - v_cartera_ventas (de 02): mismas columnas en el mismo orden, el saldo
--     descuenta lo devuelto y agrega devuelto al final.
--   - De 17 (la versión más reciente): v_cierres_caja (devoluciones_caja al
--     final), movimientos_caja_pendientes y registrar_cierre_caja.
-- =====================================================================

create table if not exists public.devoluciones (
  id                bigint generated always as identity primary key,
  venta_id          bigint not null references public.ventas(id),
  creado_en         timestamptz not null default now(),
  usuario_id        uuid references auth.users(id) default auth.uid(),
  valor             numeric(12,2) not null check (valor >= 0),        -- lo que vale lo devuelto
  a_deuda           numeric(12,2) not null default 0 check (a_deuda >= 0),   -- lo que bajó la deuda (crédito)
  reembolso         numeric(12,2) generated always as (valor - a_deuda) stored,   -- dinero que se le entregó
  forma_reembolso   text check (forma_reembolso in ('efectivo', 'transferencia')),
  motivo            text not null,
  estado            text not null default 'activa' check (estado in ('activa', 'anulada')),
  anulada_en        timestamptz,
  anulada_por       uuid references auth.users(id),
  motivo_anulacion  text,
  check (a_deuda <= valor),
  check ((valor - a_deuda > 0) = (forma_reembolso is not null))
);
create index if not exists devoluciones_venta on public.devoluciones (venta_id);
create index if not exists devoluciones_fecha on public.devoluciones (creado_en);

create table if not exists public.devolucion_detalle (
  devolucion_id     bigint not null references public.devoluciones(id) on delete cascade,
  venta_detalle_id  bigint not null references public.venta_detalle(id),
  cantidad          numeric(12,2) not null check (cantidad > 0),
  valor             numeric(12,2) not null check (valor >= 0),
  vuelve_inventario boolean not null,
  primary key (devolucion_id, venta_detalle_id)
);
create index if not exists devolucion_detalle_linea on public.devolucion_detalle (venta_detalle_id);

alter table public.devoluciones enable row level security;
alter table public.devolucion_detalle enable row level security;

drop policy if exists "leer devoluciones" on public.devoluciones;
create policy "leer devoluciones" on public.devoluciones
  for select to authenticated using (public.es_usuario_activo());
drop policy if exists "leer detalle de devoluciones" on public.devolucion_detalle;
create policy "leer detalle de devoluciones" on public.devolucion_detalle
  for select to authenticated using (public.es_usuario_activo());


-- ---------------------------------------------------------------------
-- Cartera: igual que en 02; el saldo descuenta lo devuelto.
create or replace view public.v_cartera_ventas with (security_invoker = true) as
select
  v.id,
  v.cliente_id,
  c.nombre                                               as cliente,
  v.creado_en,
  (v.creado_en at time zone 'America/Bogota')::date      as fecha,
  v.total,
  coalesce(a.abonado, 0)                                 as abonado,
  v.total - coalesce(a.abonado, 0) - coalesce(d.devuelto, 0) as saldo,
  (v.creado_en at time zone 'America/Bogota')::date + c.plazo_dias as vence_en,
  greatest(
    (now() at time zone 'America/Bogota')::date
      - ((v.creado_en at time zone 'America/Bogota')::date + c.plazo_dias),
    0)                                                   as dias_vencida,
  v.estado,
  coalesce(d.devuelto, 0)                                as devuelto
from public.ventas v
join public.clientes c on c.id = v.cliente_id
left join (
  select venta_id, sum(valor) as abonado from public.abonos group by venta_id
) a on a.venta_id = v.id
left join (
  select venta_id, sum(a_deuda) as devuelto from public.devoluciones
   where estado = 'activa' group by venta_id
) d on d.venta_id = v.id
where v.metodo_pago = 'credito'
  and v.estado <> 'anulada';


-- ---------------------------------------------------------------------
-- Para el Tablero: una fila por devolución.
create or replace view public.v_devoluciones with (security_invoker = true) as
select d.id, d.venta_id, d.creado_en,
       (d.creado_en at time zone 'America/Bogota')::date as fecha,
       d.usuario_id, d.valor, d.a_deuda, d.reembolso, d.forma_reembolso, d.motivo,
       d.estado, d.anulada_en, d.anulada_por, d.motivo_anulacion,
       v.metodo_pago,
       coalesce(c.nombre, 'Consumidor final') as cliente,
       u.nombre as usuario,
       coalesce(k.costo, 0) as costo_reintegrado   -- costo de lo que volvió al inventario
  from public.devoluciones d
  join public.ventas v on v.id = d.venta_id
  left join public.clientes c on c.id = v.cliente_id
  left join public.perfiles u on u.id = d.usuario_id
  left join (
    select dd.devolucion_id, sum(dd.cantidad * vd.costo_unitario) as costo
      from public.devolucion_detalle dd
      join public.venta_detalle vd on vd.id = dd.venta_detalle_id
     where dd.vuelve_inventario
     group by dd.devolucion_id
  ) k on k.devolucion_id = d.id;


-- ---------------------------------------------------------------------
-- Registrar una devolución.
--   p_items: [{"venta_detalle_id": 15, "cantidad": 1, "vuelve": true}, ...]
--   p_forma: 'efectivo' o 'transferencia' cuando hay dinero que entregar.
create or replace function public.registrar_devolucion(
  p_venta_id  bigint,
  p_items     jsonb,
  p_forma     text,
  p_motivo    text
)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_venta     ventas%rowtype;
  v_motivo    text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_factor    numeric;
  v_item      jsonb;
  v_linea     record;
  v_cantidad  numeric;
  v_devuelto  numeric;
  v_valor     numeric := 0;
  v_vlinea    numeric;
  v_ultima    bigint;
  v_saldo     numeric;
  v_deuda     numeric := 0;
  v_forma     text;
  v_id        bigint;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if v_motivo is null then
    raise exception 'Escribe el motivo de la devolución';
  end if;
  if length(v_motivo) > 200 then
    raise exception 'El motivo es muy largo';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Elige qué productos devuelve el cliente';
  end if;
  if (select count(distinct e->>'venta_detalle_id') from jsonb_array_elements(p_items) e)
     <> jsonb_array_length(p_items) then
    raise exception 'Un producto está repetido en la devolución';
  end if;

  -- Una devolución a la vez por venta
  select * into v_venta from ventas where id = p_venta_id for update;
  if not found then
    raise exception 'La venta % no existe', p_venta_id;
  end if;
  if v_venta.estado = 'anulada' then
    raise exception 'La venta % está anulada', p_venta_id;
  end if;

  -- Lo que el cliente pagó de verdad por cada peso de precio (descuento o recargo repartido)
  v_factor := case when v_venta.subtotal > 0 then v_venta.total / v_venta.subtotal else 0 end;

  insert into devoluciones (venta_id, valor, motivo) values (p_venta_id, 0, v_motivo)
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_cantidad := (v_item->>'cantidad')::numeric;
    if v_cantidad is null or v_cantidad <= 0 then
      raise exception 'Cantidad inválida en la devolución';
    end if;

    select vd.id, vd.presentacion_id, vd.cantidad, vd.precio_unitario,
           concat_ws(' ', p.nombre, pr.nombre) as etiqueta
      into v_linea
      from venta_detalle vd
      join presentaciones pr on pr.id = vd.presentacion_id
      join productos p on p.id = pr.producto_id
     where vd.id = (v_item->>'venta_detalle_id')::bigint and vd.venta_id = p_venta_id;
    if not found then
      raise exception 'Ese producto no está en la venta %', p_venta_id;
    end if;

    select coalesce(sum(dd.cantidad), 0) into v_devuelto
      from devolucion_detalle dd
      join devoluciones d on d.id = dd.devolucion_id and d.estado = 'activa'
     where dd.venta_detalle_id = v_linea.id;
    if v_cantidad > v_linea.cantidad - v_devuelto then
      raise exception 'De % se vendieron % y ya se devolvieron %: no se pueden devolver %',
        v_linea.etiqueta, v_linea.cantidad, v_devuelto, v_cantidad;
    end if;

    v_vlinea := round(v_cantidad * v_linea.precio_unitario * v_factor);
    insert into devolucion_detalle (devolucion_id, venta_detalle_id, cantidad, valor, vuelve_inventario)
    values (v_id, v_linea.id, v_cantidad, v_vlinea, coalesce((v_item->>'vuelve')::boolean, true));

    if coalesce((v_item->>'vuelve')::boolean, true) then
      insert into movimientos_inventario (presentacion_id, tipo, cantidad, venta_id, nota, usuario_id)
      values (v_linea.presentacion_id, 'devolucion', v_cantidad, p_venta_id,
              'Devolución ' || v_id || ': ' || v_motivo, auth.uid());
    end if;

    v_valor  := v_valor + v_vlinea;
    v_ultima := v_linea.id;
  end loop;

  -- Si con esta se devolvió todo, el total devuelto es exactamente el de la venta
  if not exists (
    select 1 from venta_detalle vd
     where vd.venta_id = p_venta_id
       and vd.cantidad > (select coalesce(sum(dd.cantidad), 0)
                            from devolucion_detalle dd
                            join devoluciones d on d.id = dd.devolucion_id and d.estado = 'activa'
                           where dd.venta_detalle_id = vd.id)) then
    v_vlinea := v_venta.total - v_valor - coalesce(
      (select sum(valor) from devoluciones where venta_id = p_venta_id and estado = 'activa' and id <> v_id), 0);
    if v_vlinea <> 0 and v_valor + v_vlinea >= 0 then
      update devolucion_detalle set valor = greatest(valor + v_vlinea, 0)
       where devolucion_id = v_id and venta_detalle_id = v_ultima;
      v_valor := v_valor + v_vlinea;
    end if;
  end if;

  -- A crédito: primero baja lo que debe
  if v_venta.metodo_pago = 'credito' then
    select greatest(coalesce(saldo, 0), 0) into v_saldo from v_cartera_ventas where id = p_venta_id;
    v_deuda := least(v_valor, coalesce(v_saldo, 0));
  end if;

  if v_valor - v_deuda > 0 then
    v_forma := p_forma;
    if v_forma is null or v_forma not in ('efectivo', 'transferencia') then
      raise exception 'Elige cómo se le devuelve el dinero al cliente (efectivo o transferencia)';
    end if;
  end if;

  update devoluciones set valor = v_valor, a_deuda = v_deuda, forma_reembolso = v_forma
   where id = v_id;

  -- La deuda quedó en cero: la venta queda pagada
  if v_venta.estado = 'pendiente_pago'
     and (select saldo from v_cartera_ventas where id = p_venta_id) <= 0 then
    update ventas set estado = 'pagada' where id = p_venta_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.registrar_devolucion(bigint, jsonb, text, text) from public, anon;
grant execute on function public.registrar_devolucion(bigint, jsonb, text, text) to authenticated;


-- ---------------------------------------------------------------------
-- Anular una devolución (solo socios). Lo que había vuelto al inventario
-- sale otra vez; la deuda regresa sola (la vista solo cuenta
-- las vigentes). Si ya entró en un cierre de caja, el siguiente lo corrige.
create or replace function public.anular_devolucion(p_id bigint, p_motivo text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_d devoluciones%rowtype;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if not es_socio() then
    raise exception 'Solo un socio puede anular una devolución';
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Indica el motivo de la anulación';
  end if;

  select * into v_d from devoluciones where id = p_id;
  if not found then
    raise exception 'La devolución % no existe', p_id;
  end if;
  perform 1 from ventas where id = v_d.venta_id for update;
  select * into v_d from devoluciones where id = p_id for update;
  if v_d.estado <> 'activa' then
    raise exception 'La devolución % ya está anulada', p_id;
  end if;

  insert into movimientos_inventario (presentacion_id, tipo, cantidad, venta_id, nota, usuario_id)
  select vd.presentacion_id, 'devolucion', -dd.cantidad, v_d.venta_id,
         'Anulación de la devolución ' || p_id || ': ' || btrim(p_motivo), auth.uid()
    from devolucion_detalle dd
    join venta_detalle vd on vd.id = dd.venta_detalle_id
   where dd.devolucion_id = p_id and dd.vuelve_inventario;

  update devoluciones
     set estado = 'anulada', anulada_en = now(), anulada_por = auth.uid(), motivo_anulacion = btrim(p_motivo)
   where id = p_id;

  -- Si había quedado pagada por la devolución, vuelve a deber
  update ventas set estado = 'pendiente_pago'
   where id = v_d.venta_id and metodo_pago = 'credito' and estado = 'pagada'
     and (select saldo from v_cartera_ventas where id = v_d.venta_id) > 0;
end;
$$;

revoke all on function public.anular_devolucion(bigint, text) from public, anon;
grant execute on function public.anular_devolucion(bigint, text) to authenticated;


-- ---------------------------------------------------------------------
-- Una venta con devoluciones vigentes no se anula.
create or replace function public.validar_anulacion_con_devolucion()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.estado = 'anulada' and old.estado <> 'anulada'
     and exists (select 1 from devoluciones where venta_id = new.id and estado = 'activa') then
    raise exception 'La venta % tiene devoluciones. Registra una devolución por lo que falta o pide a un socio que anule las devoluciones primero.', new.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.validar_anulacion_con_devolucion() from public, anon;

drop trigger if exists trg_venta_con_devolucion on public.ventas;
create trigger trg_venta_con_devolucion
  before update on public.ventas
  for each row execute function public.validar_anulacion_con_devolucion();


-- ---------------------------------------------------------------------
-- Cierre de caja: nuevo tipo y nueva columna
alter table public.cierre_caja_detalle drop constraint if exists cierre_caja_detalle_tipo_check;
alter table public.cierre_caja_detalle add constraint cierre_caja_detalle_tipo_check
  check (tipo in ('venta', 'abono', 'gasto', 'socio', 'traslado', 'devolucion'));

alter table public.cierres_caja add column if not exists devoluciones_caja numeric(12,2) not null default 0;   -- salidas: negativo

create or replace view public.v_cierres_caja
with (security_invoker = true) as
select k.id, k.creado_en, k.usuario_id, k.desde, k.base_inicial, k.ventas_efectivo, k.abonos_efectivo,
       k.gastos_caja, k.socios_caja, k.esperado, k.contado, k.diferencia, k.conteo, k.retirado,
       k.base_siguiente, k.destino, k.destino_socio_id, k.destino_nota, k.nota, k.estado,
       k.anulado_en, k.anulado_por, k.motivo_anulacion,
       u.nombre as usuario,
       s.nombre as destino_socio,
       a.nombre as anulado_por_nombre,
       k.traslados_caja,
       k.devoluciones_caja
  from public.cierres_caja k
  left join public.perfiles u on u.id = k.usuario_id
  left join public.perfiles s on s.id = k.destino_socio_id
  left join public.perfiles a on a.id = k.anulado_por;


-- ---------------------------------------------------------------------
-- Igual que en 17, más las devoluciones en efectivo (salen de la caja).
create or replace function public.movimientos_caja_pendientes(p_inicio timestamptz)
returns table (tipo text, ref_id bigint, fecha timestamptz, descripcion text, valor numeric, correccion boolean)
language sql stable security definer
set search_path = public
as $$
  with efecto as (
    select 'venta'::text as tipo, v.id as ref_id, v.creado_en as fecha,
           'Venta ' || v.id || coalesce(' · ' || c.nombre, '') as descripcion,
           case when v.estado = 'anulada' then 0 else v.total end::numeric as valor
      from ventas v
      left join clientes c on c.id = v.cliente_id
     where v.metodo_pago = 'efectivo' and v.creado_en >= p_inicio
    union all
    select 'abono', a.id, a.creado_en,
           'Abono a la venta ' || a.venta_id || coalesce(' · ' || c.nombre, ''),
           a.valor
      from abonos a
      left join clientes c on c.id = a.cliente_id
     where a.metodo_pago = 'efectivo' and a.creado_en >= p_inicio
    union all
    select 'gasto', g.id, (g.fecha::timestamp + time '12:00') at time zone 'America/Bogota',
           'Gasto · ' || g.descripcion,
           case when g.estado = 'activo' then -g.valor else 0 end
      from v_gastos g
     where g.origen = 'caja' and g.fecha >= (p_inicio at time zone 'America/Bogota')::date
    union all
    select 'socio', m.id, (m.fecha::timestamp + time '12:00') at time zone 'America/Bogota',
           case when m.tipo = 'retiro' then 'Retiro de ' else 'Reembolso a ' end || m.socio,
           case when m.estado = 'activo' then -m.valor else 0 end
      from v_movimientos_socios m
     where m.origen = 'caja' and m.fecha >= (p_inicio at time zone 'America/Bogota')::date
    union all
    select 'traslado', t.id, t.creado_en,
           'Traído de la cuenta' || coalesce(' · ' || t.nota, '') || coalesce(' · ' || p.nombre, ''),
           case when t.estado = 'activo' then t.valor else 0 end
      from traslados_caja t
      left join perfiles p on p.id = t.usuario_id
     where t.creado_en >= p_inicio
    union all
    select 'devolucion', d.id, d.creado_en,
           'Devolución de la venta ' || d.venta_id || coalesce(' · ' || c.nombre, ''),
           case when d.estado = 'activa' then -d.reembolso else 0 end
      from devoluciones d
      join ventas v on v.id = d.venta_id
      left join clientes c on c.id = v.cliente_id
     where d.forma_reembolso = 'efectivo' and d.creado_en >= p_inicio
  ), cerrado as (
    select d.tipo, d.ref_id, sum(d.valor) as valor
      from cierre_caja_detalle d
      join cierres_caja k on k.id = d.cierre_id and k.estado = 'activo'
     group by d.tipo, d.ref_id
  )
  select e.tipo, e.ref_id, e.fecha, e.descripcion,
         e.valor - coalesce(c.valor, 0),
         c.ref_id is not null
    from efecto e
    left join cerrado c on c.tipo = e.tipo and c.ref_id = e.ref_id
   where e.valor - coalesce(c.valor, 0) <> 0
   order by e.fecha, e.tipo, e.ref_id;
$$;

revoke all on function public.movimientos_caja_pendientes(timestamptz) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Igual que en 17; ahora suma y guarda las devoluciones en efectivo.
create or replace function public.registrar_cierre_caja(
  p_movimientos      numeric,
  p_contado          numeric,
  p_retirado         numeric,
  p_destino          text default null,
  p_destino_socio_id uuid default null,
  p_destino_nota     text default null,
  p_nota             text default null,
  p_conteo           jsonb default null,
  p_desde            date default null,
  p_base_inicial     numeric default null
)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_ultimo   cierres_caja%rowtype;
  v_primer   boolean;
  v_inicio   timestamptz;
  v_desde    timestamptz;
  v_base     numeric;
  v_movs     jsonb;
  v_ventas   numeric;
  v_abonos   numeric;
  v_gastos   numeric;
  v_socios   numeric;
  v_trasl    numeric;
  v_devol    numeric;
  v_total    numeric;
  v_contado  numeric := round(coalesce(p_contado, -1));
  v_retirado numeric := round(coalesce(p_retirado, 0));
  v_destino  text    := case when round(coalesce(p_retirado, 0)) > 0 then p_destino end;
  v_dnota    text    := nullif(btrim(coalesce(p_destino_nota, '')), '');
  v_nota     text    := nullif(btrim(coalesce(p_nota, '')), '');
  v_suma     numeric;
  v_id       bigint;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;

  -- Un cierre a la vez
  perform pg_advisory_xact_lock(hashtext('cierre_caja'));

  if v_contado < 0 then
    raise exception 'Escribe cuánto efectivo contaste';
  end if;
  if v_retirado < 0 then
    raise exception 'Lo retirado no puede ser negativo';
  end if;
  if v_retirado > v_contado then
    raise exception 'No se puede retirar más de lo que hay en la caja';
  end if;
  if length(v_nota) > 300 or length(v_dnota) > 200 then
    raise exception 'La nota es muy larga';
  end if;

  if p_conteo is not null then
    if jsonb_typeof(p_conteo) <> 'object' then
      raise exception 'El conteo por billetes no es válido';
    end if;
    if exists (select 1 from jsonb_each_text(p_conteo) e
                where e.key not in ('100000', '50000', '20000', '10000', '5000', '2000', '1000', '500', '200', '100', '50')
                   or e.value !~ '^\d+$') then
      raise exception 'El conteo por billetes no es válido';
    end if;
    select coalesce(sum(e.key::numeric * e.value::numeric), 0) into v_suma from jsonb_each_text(p_conteo) e;
    if v_suma <> v_contado then
      raise exception 'El conteo por billetes suma % y el total dice %', v_suma, v_contado;
    end if;
  end if;

  if v_destino is not null then
    if v_destino not in ('cuenta', 'socio', 'caja_fuerte', 'otro') then
      raise exception 'Elige a dónde va el dinero retirado';
    end if;
    if v_destino = 'socio' and not exists (
         select 1 from perfiles where id = p_destino_socio_id and activo and rol = 'socio') then
      raise exception 'Elige qué socio guarda el dinero';
    end if;
    if v_destino = 'otro' and v_dnota is null then
      raise exception 'Escribe a dónde va el dinero retirado';
    end if;
  elsif v_retirado > 0 then
    raise exception 'Elige a dónde va el dinero retirado';
  end if;

  select * into v_ultimo from cierres_caja where estado = 'activo' order by id desc limit 1;
  v_primer := not found;
  if v_primer then
    if p_desde is null then
      raise exception 'Elige desde qué fecha se acumula el efectivo';
    end if;
    if p_desde > (now() at time zone 'America/Bogota')::date then
      raise exception 'La fecha de inicio no puede ser futura';
    end if;
    v_inicio := p_desde::timestamp at time zone 'America/Bogota';
    v_desde  := v_inicio;
  else
    select min(desde) into v_inicio from cierres_caja where estado = 'activo';
    v_desde := v_ultimo.creado_en;
    v_base  := v_ultimo.base_siguiente;
  end if;

  -- Una sola lectura de los movimientos: lo que se suma es lo que se guarda
  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) into v_movs
    from movimientos_caja_pendientes(v_inicio) m;

  select coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'venta'), 0),
         coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'abono'), 0),
         coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'gasto'), 0),
         coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'socio'), 0),
         coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'traslado'), 0),
         coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'devolucion'), 0)
    into v_ventas, v_abonos, v_gastos, v_socios, v_trasl, v_devol
    from jsonb_array_elements(v_movs) x;
  v_total := v_ventas + v_abonos + v_gastos + v_socios + v_trasl + v_devol;

  if round(v_total) <> round(coalesce(p_movimientos, 0)) then
    raise exception 'Hubo movimientos de caja nuevos mientras contabas. Revisa lo esperado y registra otra vez.';
  end if;

  if v_primer then
    if p_base_inicial is null then
      v_base := v_contado - v_total;     -- lo contado se toma como correcto
      if v_base < 0 then
        raise exception 'Lo contado es menor que lo que entró en efectivo desde esa fecha. Elige una fecha más reciente o escribe con cuánto se empezó.';
      end if;
    else
      v_base := round(p_base_inicial);
      if v_base < 0 then
        raise exception 'La base inicial no puede ser negativa';
      end if;
    end if;
  end if;

  if v_contado <> v_base + v_total and v_nota is null then
    raise exception 'La caja no cuadra: escribe en la nota qué pudo pasar';
  end if;

  insert into cierres_caja (desde, base_inicial, ventas_efectivo, abonos_efectivo, gastos_caja, socios_caja, traslados_caja,
                            devoluciones_caja, esperado, contado, conteo, retirado, destino, destino_socio_id, destino_nota, nota)
  values (v_desde, v_base, v_ventas, v_abonos, v_gastos, v_socios, v_trasl, v_devol,
          v_base + v_total, v_contado, p_conteo, v_retirado, v_destino,
          case when v_destino = 'socio' then p_destino_socio_id end, v_dnota, v_nota)
  returning id into v_id;

  insert into cierre_caja_detalle (cierre_id, tipo, ref_id, valor)
  select v_id, x->>'tipo', (x->>'ref_id')::bigint, (x->>'valor')::numeric
    from jsonb_array_elements(v_movs) x;

  return v_id;
end;
$$;

revoke all on function public.registrar_cierre_caja(numeric, numeric, numeric, text, uuid, text, text, jsonb, date, numeric) from public, anon;
grant execute on function public.registrar_cierre_caja(numeric, numeric, numeric, text, uuid, text, text, jsonb, date, numeric) to authenticated;
