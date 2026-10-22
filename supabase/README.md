# Usuarios: invitar y recuperar contraseña

Configuración de Supabase para `usuarios.html` y `clave.html`. Se hace **una sola vez**, en el proyecto de la tienda (el de `SUPABASE_URL` en `config.js`, no "Café del Dormilón").

## 1. Script de base de datos

En **SQL Editor**, ejecuta `11_usuarios.sql`, después de `10_fotos_productos.sql`.

## 2. Direcciones permitidas

En **Authentication › URL Configuration**:

- **Site URL:** `https://guiral97.github.io/PinturasRebas/`
- **Redirect URLs:** agrega `https://guiral97.github.io/PinturasRebas/**`

Sin esto, el enlace del correo no abre `clave.html`.

## 3. Registro público apagado

En **Authentication › Sign In / Providers**, deja **apagado** "Allow new users to sign up". Las invitaciones siguen funcionando con el registro apagado.

## 4. Función que envía las invitaciones

1. En **Edge Functions**, entra a **Deploy a new function › Via Editor**.
2. Ponle de nombre exactamente `invitar-usuario`.
3. Borra el código de ejemplo, pega todo `supabase/functions/invitar-usuario/index.ts` y oprime **Deploy**.
4. En los ajustes de la función, deja encendido **Verify JWT** (o "Enforce JWT verification").

La función usa la llave de servicio que Supabase le pone sola. No hay que copiar ninguna llave a ningún lado.

## 5. Correo propio (necesario)

El correo que trae Supabase **solo envía a los correos del equipo de la cuenta de Supabase**, y apenas unos pocos por hora. Para que lleguen las invitaciones y la recuperación de contraseña a cualquier persona, conecta un Gmail de la tienda:

1. En esa cuenta de Google, activa la **verificación en 2 pasos** y crea una **contraseña de aplicación** (myaccount.google.com › Seguridad › Contraseñas de aplicaciones). Son 16 letras.
2. En **Authentication › Emails › SMTP Settings**, enciende **Enable custom SMTP** y llena:
   - Sender email: el Gmail de la tienda
   - Sender name: `Todo Pinturas RB`
   - Host: `smtp.gmail.com` · Port: `465`
   - Username: el Gmail de la tienda · Password: la contraseña de aplicación
3. En **Authentication › Rate Limits**, sube "Rate limit for sending emails" a unas 30 por hora.

## 6. Correos en español

En **Authentication › Emails › Templates**:

**Invite user**. Asunto: `Te invitaron a Todo Pinturas RB`

```html
<h2>Te damos la bienvenida a Todo Pinturas RB</h2>
<p>Te crearon un usuario para entrar a la app de la tienda. Abre este enlace y crea tu contraseña:</p>
<p><a href="{{ .ConfirmationURL }}">Crear mi contraseña</a></p>
<p>Si no esperabas este correo, puedes ignorarlo.</p>
```

**Reset password**. Asunto: `Recupera tu contraseña de Todo Pinturas RB`

```html
<h2>Recuperar contraseña</h2>
<p>Pediste cambiar la contraseña de la app de la tienda. Abre este enlace para crear una nueva:</p>
<p><a href="{{ .ConfirmationURL }}">Crear contraseña nueva</a></p>
<p>Si no lo pediste, ignora este correo: tu contraseña sigue igual.</p>
```

## Cómo se usa

- **Invitar:** un socio entra a **Usuarios** (en "Más" en el celular), escribe nombre, correo y rol, y oprime **Enviar invitación**. A la persona le llega el correo, abre el enlace y crea su contraseña.
- **Olvidé mi contraseña:** en cualquier pantalla de ingreso, **¿Olvidaste tu contraseña?** lleva a `clave.html`.
- **Desactivar a alguien:** en **Usuarios**, **Editar** y quita "Puede entrar a la app". La persona sigue pudiendo iniciar sesión, pero sin ver ni cambiar ningún dato.
