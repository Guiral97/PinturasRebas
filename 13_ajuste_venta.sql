-- =====================================================================
-- 13_ajuste_venta.sql — Ajuste al total en la caja: descuento o recargo
-- con motivo obligatorio.
-- Se ejecuta después de 12_catalogo_publico.sql (necesita 06 y 08).
--
-- Qué hace:
--   1. ventas.recargo (pesos que se suman al total) y ventas.ajuste_motivo.
--   2. registrar_venta_ajustada(p_venta, p_recargo, p_motivo): registra la
--      venta con registrar_venta_caja (sin reemplazarla) y, en la misma
--      transacción, guarda el motivo y suma el recargo al total.
--      Si el recargo pasa el cupo de crédito, el trigger validar_venta
--      lo rechaza y la venta no queda registrada.
--
-- El descuento sigue entrando por p_descuento de registrar_venta_caja, así
-- que el tablero lo reparte entre las líneas igual que antes. El recargo
-- cuenta en ventas, cartera y recaudo (todos leen ventas.total), pero no se
-- reparte en el margen por producto.
-- =====================================================================

alter table public.ventas
  add column if not exists recargo numeric(12,2) not null default 0 check (recargo >= 0),
  add column if not exists ajuste_motivo text;

comment on column public.ventas.recargo is 'Valor sumado al total en la caja (ya incluido en total)';
comment on column public.ventas.ajuste_motivo is 'Motivo del descuento o recargo, obligatorio si hay alguno';

-- p_venta: los parámetros de registrar_venta_caja por nombre, tal como los
-- manda la caja: p_uuid, p_items, p_cliente_id, p_metodo_pago, p_descuento,
-- p_sin_conexion y, para las ventas guardadas sin conexión, p_creada_en y
-- p_recibo_provisional.
create or replace function public.registrar_venta_ajustada(
  p_venta   jsonb,
  p_recargo numeric default 0,
  p_motivo  text default null
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_recargo   numeric := coalesce(p_recargo, 0);
  v_descuento numeric := coalesce((p_venta->>'p_descuento')::numeric, 0);
  v_motivo    text    := nullif(btrim(coalesce(p_motivo, '')), '');
  v_uuid      uuid    := (p_venta->>'p_uuid')::uuid;
  v_existia   boolean;
  v_args      text;
  v_res       jsonb;
  v_id        bigint;
  v_total     numeric;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if v_uuid is null then
    raise exception 'Falta el código de la venta';
  end if;
  if v_recargo < 0 then
    raise exception 'El recargo no puede ser negativo';
  end if;
  if v_recargo > 0 and v_descuento > 0 then
    raise exception 'Una venta lleva descuento o recargo, no los dos';
  end if;
  if (v_recargo > 0 or v_descuento > 0) and v_motivo is null then
    raise exception 'Escribe el motivo del %', case when v_recargo > 0 then 'recargo' else 'descuento' end;
  end if;
  if length(v_motivo) > 200 then
    raise exception 'El motivo es muy largo (máximo 200 caracteres)';
  end if;

  -- Reintento de una venta que ya entró: se devuelve tal cual, sin volver a sumar
  v_existia := exists (select 1 from ventas where uuid_caja = v_uuid);

  -- Llamada por nombre a registrar_venta_caja con los mismos valores que mandó
  -- la caja. Los valores van como literales sin tipo para que Postgres use los
  -- tipos que ya tiene esa función (así este script no depende de su versión).
  select string_agg(format('%I => %L', e.key, p_venta->>e.key), ', ')
    into v_args
    from jsonb_each(p_venta) e
   where e.key in ('p_uuid', 'p_items', 'p_cliente_id', 'p_metodo_pago', 'p_descuento',
                   'p_sin_conexion', 'p_creada_en', 'p_recibo_provisional');

  execute format('select public.registrar_venta_caja(%s)', v_args) into v_res;
  v_id := (v_res->>'venta_id')::bigint;

  if not v_existia and (v_recargo > 0 or v_motivo is not null) then
    update ventas
       set recargo       = v_recargo,
           ajuste_motivo = v_motivo,
           total         = total + v_recargo
     where id = v_id
     returning total into v_total;
  end if;

  v_res := v_res || jsonb_build_object('recargo', v_recargo, 'ajuste_motivo', v_motivo);
  if v_total is not null then
    v_res := v_res || jsonb_build_object('total', v_total);
  end if;
  return v_res;
end;
$$;

revoke all on function public.registrar_venta_ajustada(jsonb, numeric, text) from public, anon;
grant execute on function public.registrar_venta_ajustada(jsonb, numeric, text) to authenticated;
