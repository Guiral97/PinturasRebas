-- =====================================================================
-- 10_fotos_productos.sql · Foto de cada producto
-- Se ejecuta DESPUÉS de 09_mezclas.sql, en el SQL Editor del proyecto
-- de la tienda (el de SUPABASE_URL en config.js).
--
-- Qué hace:
--   - Agrega `productos.imagen`: la ruta de la foto dentro del bucket
--     `productos` (ej.: 12/1729600000000.webp). Una foto por producto; todas
--     sus presentaciones y partes la muestran.
--   - Crea el bucket PÚBLICO `productos` (máx. 1 MB por foto; la app la
--     reduce antes de subirla a unos 50-100 KB). Quien tenga el enlace puede
--     ver la foto, pero solo los usuarios activos pueden subirla o borrarla.
--
-- No reemplaza funciones ni vistas. `productos` es maestro: los usuarios
-- activos ya pueden actualizar la columna con las políticas de 01.
-- =====================================================================

alter table public.productos add column if not exists imagen text;
comment on column public.productos.imagen is
  'Ruta de la foto en el bucket público "productos" (ej.: 12/1729600000000.webp)';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('productos', 'productos', true, 1048576, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Ver las fotos no necesita política (el bucket es público). Estas son para
-- subir, reemplazar y borrar desde la app.
drop policy if exists "fotos productos: usuarios activos consultan" on storage.objects;
create policy "fotos productos: usuarios activos consultan" on storage.objects
  for select to authenticated
  using (bucket_id = 'productos' and public.es_usuario_activo());

drop policy if exists "fotos productos: usuarios activos suben" on storage.objects;
create policy "fotos productos: usuarios activos suben" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'productos' and public.es_usuario_activo());

drop policy if exists "fotos productos: usuarios activos cambian" on storage.objects;
create policy "fotos productos: usuarios activos cambian" on storage.objects
  for update to authenticated
  using (bucket_id = 'productos' and public.es_usuario_activo())
  with check (bucket_id = 'productos' and public.es_usuario_activo());

drop policy if exists "fotos productos: usuarios activos borran" on storage.objects;
create policy "fotos productos: usuarios activos borran" on storage.objects
  for delete to authenticated
  using (bucket_id = 'productos' and public.es_usuario_activo());
