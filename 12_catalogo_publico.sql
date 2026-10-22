-- =====================================================================
-- 12_catalogo_publico.sql · Catálogo público (catalogo.html)
-- Se ejecuta DESPUÉS de 11_usuarios.sql, en el SQL Editor del proyecto
-- de la tienda (el de SUPABASE_URL en config.js).
--
-- Qué hace:
--   - Agrega `productos.publicado`: si el producto sale en el catálogo
--     público. Por defecto NO: cada producto se publica a mano desde
--     Inventario (casilla "Publicar en el catálogo").
--   - catalogo_publico(): lo único que puede consultar alguien sin sesión.
--     Devuelve los productos activos y publicados con nombre, marca,
--     categoría, código de color, descripción, foto y sus presentaciones
--     activas con disponibilidad en palabras (si / pocas / no).
--     NUNCA devuelve precios, costos, stock exacto, clientes ni proveedores.
--
-- Las tablas siguen cerradas para anon (RLS). No reemplaza funciones ni
-- vistas: solo lee v_catalogo (de 08) para el stock vendible.
-- =====================================================================

alter table public.productos add column if not exists publicado boolean not null default false;
comment on column public.productos.publicado is
  'Si el producto sale en el catálogo público (catalogo.html)';

create or replace function public.catalogo_publico()
returns table (
  id               bigint,
  nombre           text,
  marca            text,
  categoria        text,
  codigo_color     text,
  descripcion      text,
  imagen           text,      -- ruta en el bucket público "productos"
  con_catalizador  boolean,   -- tiene venta completa (09_mezclas)
  presentaciones   jsonb      -- [{ nombre, parte, disponible: 'si' | 'pocas' | 'no' }]
)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.nombre, m.nombre, c.nombre, p.codigo_color, p.descripcion, p.imagen,
         exists (select 1 from mezclas x
                 join presentaciones px on px.id = x.presentacion_id
                 where px.producto_id = p.id),
         jsonb_agg(jsonb_build_object(
           'nombre', pr.nombre,
           'parte', pr.madre_id is not null,
           'disponible', case
             when coalesce(v.stock, 0) <= 0 then 'no'
             when v.stock <= pr.stock_minimo then 'pocas'
             else 'si' end
         ) order by pr.madre_id nulls first, coalesce(v.fraccion, 1) desc, pr.id)
  from productos p
  join presentaciones pr on pr.producto_id = p.id and pr.activo
  left join v_catalogo v on v.id = pr.id
  left join marcas m on m.id = p.marca_id
  left join categorias c on c.id = p.categoria_id
  where p.activo and p.publicado
  group by p.id, m.nombre, c.nombre
  order by c.nombre nulls last, p.nombre;
$$;

revoke all on function public.catalogo_publico() from public;
grant execute on function public.catalogo_publico() to anon, authenticated;

-- Opcional: para publicar de una vez todos los productos activos, quita
-- los dos guiones de la línea siguiente y ejecútala (después se pueden
-- despublicar uno por uno en Inventario).
-- update public.productos set publicado = true where activo;
