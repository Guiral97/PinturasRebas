-- =====================================================================
--  03: Tablero de ventas
--  Ejecutar en Supabase > SQL Editor DESPUÉS de 01 y 02
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Detalle de ventas "plano": una fila por producto vendido.
--    El descuento de la venta se reparte entre sus líneas en proporción
--    a su valor, para que el margen por producto sea real.
--    Es la tabla de hechos ideal para Power BI.
-- ---------------------------------------------------------------------
create view public.v_ventas_detalle with (security_invoker = true) as
select
  v.id                                                        as venta_id,
  v.creado_en,
  (v.creado_en at time zone 'America/Bogota')::date           as fecha,
  extract(hour from v.creado_en at time zone 'America/Bogota')::int as hora,
  v.estado,
  v.metodo_pago,
  coalesce(pf.nombre, 'Sin usuario')                          as vendedor,
  coalesce(cl.nombre, 'Consumidor final')                     as cliente,
  coalesce(cl.tipo, 'particular')                             as cliente_tipo,
  coalesce(ca.nombre, 'Sin categoría')                        as categoria,
  coalesce(ma.nombre, 'Sin marca')                            as marca,
  p.nombre                                                    as producto,
  pr.nombre                                                   as presentacion,
  concat_ws(' ', ma.nombre, p.nombre, p.codigo_color, pr.nombre) as etiqueta,
  vd.presentacion_id,
  vd.cantidad,
  vd.precio_unitario,
  vd.costo_unitario,
  vd.subtotal,
  d.descuento_linea                                           as descuento,
  vd.subtotal - d.descuento_linea                             as venta_neta,
  vd.cantidad * vd.costo_unitario                             as costo_total,
  vd.subtotal - d.descuento_linea - vd.cantidad * vd.costo_unitario as margen
from public.venta_detalle vd
join public.ventas v            on v.id = vd.venta_id
join public.presentaciones pr   on pr.id = vd.presentacion_id
join public.productos p         on p.id = pr.producto_id
left join public.marcas ma      on ma.id = p.marca_id
left join public.categorias ca  on ca.id = p.categoria_id
left join public.clientes cl    on cl.id = v.cliente_id
left join public.perfiles pf    on pf.id = v.usuario_id
cross join lateral (
  select round(case when v.subtotal > 0 then vd.subtotal / v.subtotal * v.descuento else 0 end, 2)
         as descuento_linea
) d;


-- ---------------------------------------------------------------------
-- 2. Resumen del período en una sola llamada (para el tablero web)
--    Excluye ventas anuladas. Fechas en hora de Colombia.
-- ---------------------------------------------------------------------
create or replace function public.resumen_ventas(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable
set search_path = public
as $$
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'Rango de fechas inválido';
  end if;
  if p_hasta - p_desde > 400 then
    raise exception 'El rango máximo es de 400 días';
  end if;

  return (
    with v as (
      select ve.*,
             (ve.creado_en at time zone 'America/Bogota')::date as fecha,
             coalesce(pf.nombre, 'Sin usuario') as vendedor
        from ventas ve
        left join perfiles pf on pf.id = ve.usuario_id
       where (ve.creado_en at time zone 'America/Bogota')::date between p_desde and p_hasta
    ),
    va as (select * from v where estado <> 'anulada'),
    d  as (select * from v_ventas_detalle
            where fecha between p_desde and p_hasta and estado <> 'anulada'),
    ab as (select coalesce(sum(valor), 0) as total
             from abonos
            where (creado_en at time zone 'America/Bogota')::date between p_desde and p_hasta)
    select jsonb_build_object(
      'kpis', (
        select jsonb_build_object(
          'ventas_netas',     coalesce(sum(total), 0),
          'num_ventas',       count(*),
          'ticket_promedio',  coalesce(round(avg(total)), 0),
          'descuentos',       coalesce(sum(descuento), 0),
          'credito_otorgado', coalesce(sum(total) filter (where metodo_pago = 'credito'), 0),
          'abonos',           (select total from ab),
          'recaudo',          coalesce(sum(total) filter (where metodo_pago <> 'credito'), 0)
                                + (select total from ab),
          'anuladas',         (select count(*) from v where estado = 'anulada')
        ) from va
      ),
      'margen', (
        select jsonb_build_object(
          'costo',    coalesce(sum(costo_total), 0),
          'margen',   coalesce(sum(margen), 0),
          'unidades', coalesce(sum(cantidad), 0)
        ) from d
      ),
      'por_dia', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'fecha', g.dia::date, 'total', coalesce(x.total, 0), 'ventas', coalesce(x.n, 0))
                 order by g.dia), '[]'::jsonb)
          from generate_series(p_desde, p_hasta, interval '1 day') g(dia)
          left join (select fecha, sum(total) as total, count(*) as n from va group by fecha) x
                 on x.fecha = g.dia::date
      ),
      'por_metodo', (
        select coalesce(jsonb_agg(jsonb_build_object('metodo', metodo_pago, 'total', t, 'ventas', n)
                 order by t desc), '[]'::jsonb)
          from (select metodo_pago, sum(total) as t, count(*) as n from va group by metodo_pago) s
      ),
      'por_vendedor', (
        select coalesce(jsonb_agg(jsonb_build_object('vendedor', vendedor, 'total', t, 'ventas', n)
                 order by t desc), '[]'::jsonb)
          from (select vendedor, sum(total) as t, count(*) as n from va group by vendedor) s
      ),
      'por_categoria', (
        select coalesce(jsonb_agg(jsonb_build_object('categoria', categoria, 'total', t, 'margen', m)
                 order by t desc), '[]'::jsonb)
          from (select categoria, sum(venta_neta) as t, sum(margen) as m from d group by categoria) s
      ),
      'top_productos', (
        select coalesce(jsonb_agg(jsonb_build_object('etiqueta', etiqueta, 'unidades', u, 'total', t, 'margen', m)
                 order by t desc), '[]'::jsonb)
          from (select etiqueta, sum(cantidad) as u, sum(venta_neta) as t, sum(margen) as m
                  from d group by presentacion_id, etiqueta
                 order by t desc limit 10) s
      )
    )
  );
end;
$$;

revoke execute on function public.resumen_ventas(date, date) from public, anon;
grant  execute on function public.resumen_ventas(date, date) to authenticated;


-- ---------------------------------------------------------------------
-- 3. OPCIONAL: usuario de solo lectura para Power BI
--    Power BI se conecta directo a Postgres, sin sesión de Supabase,
--    así que necesita su propio rol con permiso de lectura.
--    Quita los comentarios, cambia la contraseña y ejecuta.
-- ---------------------------------------------------------------------
-- create role lector_bi with login password 'CAMBIA-ESTA-CLAVE-LARGA';
-- grant usage on schema public to lector_bi;
-- grant select on
--   public.v_ventas_detalle, public.v_catalogo, public.v_stock_bajo,
--   public.v_cartera_ventas, public.v_cartera_clientes
--   to lector_bi;
--
-- -- Las vistas respetan RLS, así que el rol necesita poder leer las tablas base
-- do $$
-- declare t text;
-- begin
--   foreach t in array array[
--     'ventas', 'venta_detalle', 'presentaciones', 'productos', 'marcas', 'categorias',
--     'clientes', 'perfiles', 'movimientos_inventario', 'abonos'
--   ] loop
--     execute format('grant select on public.%I to lector_bi', t);
--     execute format('create policy "lectura power bi" on public.%I for select to lector_bi using (true)', t);
--   end loop;
-- end $$;
