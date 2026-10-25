-- =====================================================================
-- 16_liquidos_producto.sql · Líquido vinculado a su producto
-- Se ejecuta DESPUÉS de 15_conversiones.sql, en el SQL Editor del proyecto
-- de la tienda (el de SUPABASE_URL en config.js).
--
-- Qué hace:
--   Agrega liquidos.producto_id (opcional): el producto del inventario que
--   es ese líquido (ej. el líquido "Ajustador" -> el producto Ajustador).
--   Con el vínculo, la caja sugiere en la línea cuántos gramos pesar según
--   la presentación vendida (Galón, Media, 1/4… o una parte).
--   Un producto tiene a lo sumo un líquido. Si se borra el producto, el
--   líquido queda sin vínculo.
--
--   No reemplaza funciones ni vistas.
-- =====================================================================

alter table public.liquidos
  add column if not exists producto_id bigint references public.productos(id) on delete set null;

create unique index if not exists liquidos_producto_unico
  on public.liquidos (producto_id) where producto_id is not null;

comment on column public.liquidos.producto_id is
  'Producto del inventario que es este líquido; la caja sugiere los gramos a pesar de sus presentaciones.';
