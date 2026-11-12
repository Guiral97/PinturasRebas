-- =====================================================================
-- 19_cambiar_forma_abono.sql
-- Corregir la forma de pago de un abono mal registrado (p. ej. se guardó
-- en efectivo y fue por transferencia), desde el historial de Cartera.
--
-- Se ejecuta DESPUÉS de 18_devoluciones.sql (usa es_socio() de 11 y
-- cierres_caja de 14). No reemplaza funciones ni vistas.
--
-- - abonos: columnas de auditoría del cambio (forma original, quién,
--   cuándo y motivo).
-- - cambiar_forma_abono(p_abono_id, p_metodo, p_referencia, p_motivo):
--   cambia todo el abono (las filas que se registraron juntas, una por
--   factura). Puede hacerlo un socio o quien registró el abono.
--   No deja cambiar un abono que ya quedó dentro de un cierre de caja
--   activo: ese cierre ya contó (o no) ese dinero. Primero hay que anular
--   los cierres desde entonces (se anulan del último hacia atrás).
--   Si el abono es posterior al último cierre, el siguiente cierre lo
--   toma con la forma corregida sin hacer nada más.
-- =====================================================================

alter table public.abonos
  add column if not exists metodo_original      text,
  add column if not exists metodo_cambiado_por  uuid,
  add column if not exists metodo_cambiado_en   timestamptz,
  add column if not exists metodo_cambio_motivo text;

create or replace function public.cambiar_forma_abono(
  p_abono_id   bigint,
  p_metodo     text,
  p_referencia text default null,
  p_motivo     text default null
)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v_a       abonos%rowtype;
  v_inicio  timestamptz;
  v_cierre  timestamptz;
  v_n       integer;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_metodo is null or p_metodo not in ('efectivo', 'transferencia', 'tarjeta') then
    raise exception 'Forma de pago no válida para un abono';
  end if;

  select * into v_a from abonos where id = p_abono_id for update;
  if not found then
    raise exception 'No se encontró el abono';
  end if;
  if not es_socio() and v_a.usuario_id is distinct from auth.uid() then
    raise exception 'Solo un socio o quien registró el abono puede cambiar su forma de pago';
  end if;
  if v_a.metodo_pago = p_metodo then
    raise exception 'El abono ya está registrado con esa forma de pago';
  end if;

  -- ¿Ya quedó dentro de un cierre de caja activo?
  select min(desde) into v_inicio from cierres_caja where estado = 'activo';
  select min(creado_en) into v_cierre
    from cierres_caja
   where estado = 'activo' and creado_en >= v_a.creado_en;
  if v_inicio is not null and v_a.creado_en >= v_inicio and v_cierre is not null then
    raise exception 'Este abono ya quedó dentro del cierre de caja del %. Para cambiarlo, un socio debe anular primero los cierres hechos desde ese día (se anulan del último hacia atrás).',
      to_char(v_cierre at time zone 'America/Bogota', 'DD/MM/YYYY HH12:MI am');
  end if;

  -- Todas las filas del mismo abono (repartido entre varias facturas)
  update abonos
     set metodo_original      = coalesce(metodo_original, metodo_pago),
         metodo_pago          = p_metodo,
         referencia           = coalesce(nullif(btrim(p_referencia), ''), referencia),
         metodo_cambiado_por  = auth.uid(),
         metodo_cambiado_en   = now(),
         metodo_cambio_motivo = nullif(btrim(p_motivo), '')
   where cliente_id = v_a.cliente_id
     and creado_en  = v_a.creado_en
     and usuario_id is not distinct from v_a.usuario_id
     and metodo_pago = v_a.metodo_pago;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function public.cambiar_forma_abono(bigint, text, text, text) from public, anon;
grant  execute on function public.cambiar_forma_abono(bigint, text, text, text) to authenticated;
