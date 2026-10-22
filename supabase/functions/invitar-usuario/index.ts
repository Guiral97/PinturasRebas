// Edge Function "invitar-usuario": un socio invita a una persona a la app.
// Le llega un correo para crear su contraseña (clave.html) y queda con perfil activo.
//
// Usa la llave de servicio, que Supabase pone sola en el entorno de la función:
// NUNCA va en la app ni en este archivo. Antes de invitar, comprueba con la
// sesión de quien llama que es socio (es_socio(), de 11_usuarios.sql).
//
// Recibe (POST, JSON): { nombre, email, rol: 'socio' | 'vendedor', redirectTo }
// Si la persona ya fue invitada y no ha entrado, vuelve a enviar el correo.
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const respuesta = (status: number, cuerpo: Record<string, unknown>) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return respuesta(405, { error: 'Método no permitido.' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const servicio = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Quién llama: con su propia sesión, así es_socio() mira su usuario
  const comoUsuario = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: esSocio, error: errSocio } = await comoUsuario.rpc('es_socio');
  if (errSocio || !esSocio) return respuesta(403, { error: 'Solo un socio puede invitar usuarios.' });

  let datos: Record<string, unknown>;
  try { datos = await req.json(); } catch { return respuesta(400, { error: 'Datos inválidos.' }); }
  const email = String(datos.email ?? '').trim().toLowerCase();
  const nombre = String(datos.nombre ?? '').trim();
  const rol = datos.rol === 'socio' ? 'socio' : 'vendedor';
  const redirectTo = typeof datos.redirectTo === 'string' && datos.redirectTo ? datos.redirectTo : undefined;
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return respuesta(400, { error: 'Escribe un correo válido.' });
  if (!nombre) return respuesta(400, { error: 'Escribe el nombre.' });

  const admin = createClient(url, servicio, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo, data: { nombre } });
  if (error) {
    if (/already|registered|exists/i.test(error.message)) {
      return respuesta(409, { codigo: 'ya_registrado', error: 'Ese correo ya tiene una cuenta.' });
    }
    if (/rate limit/i.test(error.message)) {
      return respuesta(429, { error: 'Supabase no deja enviar más correos por ahora. Intenta en una hora o configura el correo propio (supabase/README.md).' });
    }
    return respuesta(400, { error: 'No se pudo enviar la invitación: ' + error.message });
  }

  // Perfil activo; si ya existía (invitación reenviada), se deja como está
  const { error: errPerfil } = await admin.from('perfiles')
    .upsert({ id: data.user.id, nombre, rol, activo: true }, { onConflict: 'id', ignoreDuplicates: true });
  if (errPerfil) return respuesta(500, { error: 'Se envió el correo, pero no se pudo crear el perfil: ' + errPerfil.message });

  return respuesta(200, { ok: true, id: data.user.id });
});
