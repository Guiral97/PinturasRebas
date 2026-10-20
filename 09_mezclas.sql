-- =====================================================================
-- 09_mezclas.sql · Venta "completa" (producto + catalizador)
-- Se ejecuta DESPUÉS de 08_fracciones.sql, en el SQL Editor del proyecto
-- de la tienda (el de SUPABASE_URL en config.js).
--
-- Qué hace:
--   Crea la tabla maestra `mezclas`: qué catalizador lleva una presentación
--   y en qué proporción. Ej.: por cada Galón de Poliuretano X va 1/4 de
--   Galón de Catalizador X  ->  proporcion = 0.25.
--
--   La caja usa la regla para calcular cuánto catalizador corresponde a la
--   medida vendida (Galón, 1/4, 1/8…, o una parte de la "venta por partes")
--   y lo agrega como otra línea de la venta. No cambia registrar_venta ni
--   registrar_venta_caja: el catalizador se vende como cualquier
--   presentación (precio de la base de datos, descuenta su propio stock).
--
--   Ambas presentaciones deben ser "completas" (sin madre_id): la regla de
--   la madre aplica también a sus partes.
-- =====================================================================

create table if not exists public.mezclas (
  id               bigint generated always as identity primary key,
  presentacion_id  bigint not null unique references public.presentaciones(id) on delete cascade,
  catalizador_id   bigint not null references public.presentaciones(id) on delete cascade,
  -- Unidades de la presentación del catalizador por cada unidad de la base
  proporcion       numeric(12,6) not null check (proporcion > 0),
  creado_en        timestamptz not null default now(),
  constraint mezclas_distintas check (presentacion_id <> catalizador_id)
);

comment on table public.mezclas is
  'Venta completa: catalizador que lleva una presentación y en qué proporción (unidades del catalizador por unidad de la base).';

-- Las dos deben ser presentaciones completas (no partes)
create or replace function public.validar_mezcla()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (select 1 from presentaciones where id = new.presentacion_id and madre_id is not null) then
    raise exception 'El producto de la mezcla debe ser una presentación completa (la regla aplica también a sus partes).';
  end if;
  if exists (select 1 from presentaciones where id = new.catalizador_id and madre_id is not null) then
    raise exception 'El catalizador debe ser una presentación completa; la caja elige sola la parte que corresponde.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_mezcla on public.mezclas;
create trigger trg_validar_mezcla
  before insert or update on public.mezclas
  for each row execute function public.validar_mezcla();

-- Maestro: los usuarios activos leen y escriben directo
alter table public.mezclas enable row level security;

drop policy if exists mezclas_usuarios_activos on public.mezclas;
create policy mezclas_usuarios_activos on public.mezclas
  for all to authenticated
  using (public.es_usuario_activo())
  with check (public.es_usuario_activo());

revoke all on public.mezclas from public, anon;
grant select, insert, update, delete on public.mezclas to authenticated;
