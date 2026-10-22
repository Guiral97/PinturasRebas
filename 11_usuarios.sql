-- =====================================================================
-- 11_usuarios.sql · Administrar usuarios desde la app (solo socios)
-- Se ejecuta DESPUÉS de 10_fotos_productos.sql, en el SQL Editor del
-- proyecto de la tienda (el de SUPABASE_URL en config.js).
--
-- Qué hace:
--   - es_socio(): true si quien consulta es un usuario activo con rol 'socio'.
--   - listar_usuarios(): perfiles con su correo, último ingreso y si aún no
--     ha creado su contraseña (invitación pendiente). Solo socios.
--   - actualizar_usuario(): cambia nombre, rol y si está activo. Solo socios;
--     nadie puede desactivarse ni quitarse el rol de socio a sí mismo.
--
-- La invitación de usuarios nuevos NO está aquí: crear una cuenta necesita la
-- llave de servicio, que nunca va en la app. La hace la Edge Function
-- supabase/functions/invitar-usuario (ver supabase/README.md).
-- El registro público de usuarios sigue desactivado.
-- =====================================================================

create or replace function public.es_socio()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles where id = auth.uid() and activo and rol = 'socio'
  );
$$;

create or replace function public.listar_usuarios()
returns table (
  id             uuid,
  nombre         text,
  email          text,
  rol            text,
  activo         boolean,
  creado_en      timestamptz,
  ultimo_ingreso timestamptz,
  pendiente      boolean      -- invitado que todavía no ha creado su contraseña
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  if not public.es_socio() then
    raise exception 'Solo un socio puede ver los usuarios.';
  end if;
  return query
  select p.id, p.nombre, u.email::text, p.rol, p.activo, p.creado_en, u.last_sign_in_at,
         coalesce(u.encrypted_password, '') = ''
  from public.perfiles p
  join auth.users u on u.id = p.id
  order by p.activo desc, p.nombre;
end;
$$;

create or replace function public.actualizar_usuario(
  p_id     uuid,
  p_nombre text,
  p_rol    text,
  p_activo boolean
)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.es_socio() then
    raise exception 'Solo un socio puede cambiar usuarios.';
  end if;
  if coalesce(trim(p_nombre), '') = '' then
    raise exception 'Escribe el nombre del usuario.';
  end if;
  if p_rol not in ('socio', 'vendedor') then
    raise exception 'El rol debe ser socio o vendedor.';
  end if;
  if p_id = auth.uid() and (not p_activo or p_rol <> 'socio') then
    raise exception 'No puedes desactivarte ni quitarte el rol de socio a ti mismo. Pídeselo a otro socio.';
  end if;

  update public.perfiles
     set nombre = trim(p_nombre), rol = p_rol, activo = p_activo
   where id = p_id;
  if not found then
    raise exception 'Ese usuario no existe.';
  end if;
end;
$$;

revoke all on function public.es_socio() from public, anon;
revoke all on function public.listar_usuarios() from public, anon;
revoke all on function public.actualizar_usuario(uuid, text, text, boolean) from public, anon;
grant execute on function public.es_socio() to authenticated;
grant execute on function public.listar_usuarios() to authenticated;
grant execute on function public.actualizar_usuario(uuid, text, text, boolean) to authenticated;
