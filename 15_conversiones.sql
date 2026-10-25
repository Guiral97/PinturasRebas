-- =====================================================================
-- 15_conversiones.sql · Conversiones de líquidos (volumen -> peso)
-- Se ejecuta DESPUÉS de 14_cierre_caja.sql, en el SQL Editor del proyecto
-- de la tienda (el de SUPABASE_URL en config.js).
--
-- Qué hace:
--   Crea dos tablas maestras que usa la pantalla conversiones.html para
--   decir cuántos gramos hay que pesar en la balanza para despachar una
--   medida de un líquido. Ej.: una "media" (1/10 de galón = 378,5 ml) de
--   ajustador con densidad 0,87 g/ml pesa 329 g, no 378 g como el agua.
--
--   - liquidos: nombre y densidad (g/ml). En la pantalla se puede escribir
--     la densidad de la ficha técnica o el peso neto de un galón.
--   - medidas_liquido: medidas con su nombre tradicional y la fracción de
--     galón que representan (Galón 1, Media 1/10, Cuarto 1/4…).
--
--   Es solo de consulta: no toca ventas, inventario ni presentaciones.
--   No reemplaza funciones ni vistas.
-- =====================================================================

create table if not exists public.liquidos (
  id              bigint generated always as identity primary key,
  nombre          text not null,
  -- Gramos por mililitro (agua = 1; ajustadores y thinner suelen ir de 0,80 a 0,90)
  densidad        numeric(8,4) not null check (densidad between 0.3 and 3),
  notas           text,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  constraint liquidos_nombre_lleno check (btrim(nombre) <> '')
);
create unique index if not exists liquidos_nombre_unico on public.liquidos (lower(btrim(nombre)));

comment on table public.liquidos is
  'Líquidos que se despachan pesando: densidad en g/ml para pasar de volumen a gramos (conversiones.html).';

create table if not exists public.medidas_liquido (
  id        bigint generated always as identity primary key,
  nombre    text not null,
  -- Fracción de galón (3.785,41 ml): Galón 1, Media 0.1, Cuarto 0.25…
  fraccion  numeric(12,8) not null check (fraccion > 0 and fraccion <= 100),
  constraint medidas_liquido_nombre_lleno check (btrim(nombre) <> '')
);
create unique index if not exists medidas_liquido_nombre_unico on public.medidas_liquido (lower(btrim(nombre)));

comment on table public.medidas_liquido is
  'Medidas tradicionales de venta de líquidos como fracción de galón (conversiones.html).';

-- Medidas de siempre (solo si la tabla está vacía)
insert into public.medidas_liquido (nombre, fraccion)
select v.nombre, v.fraccion
from (values
  ('Galón',  1::numeric),
  ('Cuarto', 0.25),
  ('Octavo', 0.125),
  ('Media',  0.1),
  ('1/16',   0.0625),
  ('1/32',   0.03125)
) as v(nombre, fraccion)
where not exists (select 1 from public.medidas_liquido);

-- Nombre sin espacios sobrantes y fecha de cambio
create or replace function public.limpiar_liquido()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.nombre := btrim(new.nombre);
  new.notas := nullif(btrim(coalesce(new.notas, '')), '');
  new.actualizado_en := now();
  return new;
end;
$$;

drop trigger if exists trg_limpiar_liquido on public.liquidos;
create trigger trg_limpiar_liquido
  before insert or update on public.liquidos
  for each row execute function public.limpiar_liquido();

-- Maestros: los usuarios activos leen y escriben directo
alter table public.liquidos enable row level security;
alter table public.medidas_liquido enable row level security;

drop policy if exists liquidos_usuarios_activos on public.liquidos;
create policy liquidos_usuarios_activos on public.liquidos
  for all to authenticated
  using (public.es_usuario_activo())
  with check (public.es_usuario_activo());

drop policy if exists medidas_liquido_usuarios_activos on public.medidas_liquido;
create policy medidas_liquido_usuarios_activos on public.medidas_liquido
  for all to authenticated
  using (public.es_usuario_activo())
  with check (public.es_usuario_activo());

revoke all on public.liquidos, public.medidas_liquido from public, anon;
grant select, insert, update, delete on public.liquidos, public.medidas_liquido to authenticated;
