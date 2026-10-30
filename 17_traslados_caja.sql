-- =====================================================================
-- 17_traslados_caja.sql — Traer dinero de la cuenta a la caja (por ejemplo,
-- sencillo para dar cambio o plata para pagar algo en efectivo).
-- Se ejecuta después de 16_liquidos_producto.sql (necesita 11 y 14).
--
-- Qué hace:
--   1. traslados_caja: cada vez que se saca dinero de la cuenta del negocio y
--      se mete en la caja (valor, nota, quién, anulación).
--   2. registrar_traslado_caja(p_valor, p_nota): cualquier usuario activo.
--   3. anular_traslado_caja(p_id, p_motivo): un socio o quien lo registró.
--   4. Cierre de caja: el traslado suma a lo que debería haber. Agrega la
--      columna cierres_caja.traslados_caja y el tipo 'traslado' en
--      cierre_caja_detalle.
--
-- Reemplaza (copiadas de 14, la versión más reciente): v_cierres_caja (mismas
-- columnas en el mismo orden y traslados_caja al final),
-- movimientos_caja_pendientes y registrar_cierre_caja.
-- =====================================================================

create table if not exists public.traslados_caja (
  id                bigint generated always as identity primary key,
  creado_en         timestamptz not null default now(),
  usuario_id        uuid references auth.users(id) default auth.uid(),
  valor             numeric(12,2) not null check (valor > 0),
  nota              text,
  estado            text not null default 'activo' check (estado in ('activo', 'anulado')),
  anulado_en        timestamptz,
  anulado_por       uuid references auth.users(id),
  motivo_anulacion  text
);

alter table public.traslados_caja enable row level security;

drop policy if exists "leer traslados de caja" on public.traslados_caja;
create policy "leer traslados de caja" on public.traslados_caja
  for select to authenticated using (public.es_usuario_activo());


-- ---------------------------------------------------------------------
create or replace function public.registrar_traslado_caja(p_valor numeric, p_nota text default null)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_valor numeric := round(coalesce(p_valor, 0));
  v_nota  text    := nullif(btrim(coalesce(p_nota, '')), '');
  v_id    bigint;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if v_valor <= 0 then
    raise exception 'Escribe cuánto dinero se trae de la cuenta';
  end if;
  if v_valor > 9999999999 then
    raise exception 'El valor es demasiado grande';
  end if;
  if length(v_nota) > 200 then
    raise exception 'La nota es muy larga';
  end if;

  insert into traslados_caja (valor, nota) values (v_valor, v_nota) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.registrar_traslado_caja(numeric, text) from public, anon;
grant execute on function public.registrar_traslado_caja(numeric, text) to authenticated;


-- ---------------------------------------------------------------------
-- Si el traslado ya entró en un cierre, el siguiente lo descuenta como corrección.
create or replace function public.anular_traslado_caja(p_id bigint, p_motivo text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_t traslados_caja%rowtype;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Indica el motivo de la anulación';
  end if;

  select * into v_t from traslados_caja where id = p_id for update;
  if not found or v_t.estado <> 'activo' then
    raise exception 'El traslado % no existe o ya está anulado', p_id;
  end if;
  if v_t.usuario_id is distinct from auth.uid() and not es_socio() then
    raise exception 'Solo un socio o quien lo registró puede anular este traslado';
  end if;

  update traslados_caja
     set estado = 'anulado', anulado_en = now(), anulado_por = auth.uid(), motivo_anulacion = btrim(p_motivo)
   where id = p_id;
end;
$$;

revoke all on function public.anular_traslado_caja(bigint, text) from public, anon;
grant execute on function public.anular_traslado_caja(bigint, text) to authenticated;


-- ---------------------------------------------------------------------
-- Cierre de caja: nuevo tipo y nueva columna
alter table public.cierre_caja_detalle drop constraint if exists cierre_caja_detalle_tipo_check;
alter table public.cierre_caja_detalle add constraint cierre_caja_detalle_tipo_check
  check (tipo in ('venta', 'abono', 'gasto', 'socio', 'traslado'));

alter table public.cierres_caja add column if not exists traslados_caja numeric(12,2) not null default 0;   -- entradas: positivo

create or replace view public.v_cierres_caja
with (security_invoker = true) as
select k.id, k.creado_en, k.usuario_id, k.desde, k.base_inicial, k.ventas_efectivo, k.abonos_efectivo,
       k.gastos_caja, k.socios_caja, k.esperado, k.contado, k.diferencia, k.conteo, k.retirado,
       k.base_siguiente, k.destino, k.destino_socio_id, k.destino_nota, k.nota, k.estado,
       k.anulado_en, k.anulado_por, k.motivo_anulacion,
       u.nombre as usuario,
       s.nombre as destino_socio,
       a.nombre as anulado_por_nombre,
       k.traslados_caja
  from public.cierres_caja k
  left join public.perfiles u on u.id = k.usuario_id
  left join public.perfiles s on s.id = k.destino_socio_id
  left join public.perfiles a on a.id = k.anulado_por;


-- ---------------------------------------------------------------------
-- Igual que en 14, más los traslados de la cuenta (entran a la caja).
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
-- Igual que en 14; ahora suma y guarda los traslados.
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
         coalesce(sum((x->>'valor')::numeric) filter (where x->>'tipo' = 'traslado'), 0)
    into v_ventas, v_abonos, v_gastos, v_socios, v_trasl
    from jsonb_array_elements(v_movs) x;
  v_total := v_ventas + v_abonos + v_gastos + v_socios + v_trasl;

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
                            esperado, contado, conteo, retirado, destino, destino_socio_id, destino_nota, nota)
  values (v_desde, v_base, v_ventas, v_abonos, v_gastos, v_socios, v_trasl,
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
