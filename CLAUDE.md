# Todo Pinturas RB: app de caja, inventario y cartera

Claude Code lee este archivo al abrir la carpeta. Responde **siempre en español** (interfaz, mensajes de error, comentarios y textos para el usuario).

## Qué es

Tienda de **pintura automotriz y accesorios** en Medellín, con tres socios. Antes se llamaba "Pinturas Rebas"; el nombre visible sale de `NOMBRE_TIENDA` en `config.js`. La app cubre caja (ventas con lector de código de barras), cotizaciones, pedidos, inventario, cartera (crédito y abonos), gastos y tablero. Todo con opciones gratuitas.

- Moneda: pesos colombianos (COP), sin decimales en pantalla (`Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 })`).
- Zona horaria: `America/Bogota`. Los cortes de día y los vencimientos se calculan en esa zona, no en UTC.
- Usuarios: los socios y los vendedores que ellos inviten, cada uno con fila en `perfiles` (`rol` = `socio` o `vendedor`). Solo los socios administran usuarios.

## Arquitectura

- **Frontend:** HTML, CSS y JavaScript puros, **sin build ni npm**. Un archivo por pantalla. Publicado en GitHub Pages desde el repo público `Guiral97/PinturasRebas` (rama `main`) → `https://guiral97.github.io/PinturasRebas/`.
- **Librerías por CDN** (no agregar otras sin necesidad): `@supabase/supabase-js@2` (jsDelivr), `html5-qrcode@2.3.8` (cámara), `chart.js@4.4.1` (tablero), `qrcode-generator@1.4.4` (tarjeta del catálogo).
- **Backend:** Supabase plan gratuito (Postgres + Auth + Storage). Límites: 500 MB de base de datos, 1 GB de Storage, 5 GB de transferencia al mes, el proyecto se pausa tras 7 días sin uso, sin respaldos automáticos.
- **Respaldo:** GitHub Action diaria (`respaldo-diario.yml`) en un repo **privado aparte**: consulta la API (evita la pausa) y guarda un volcado 60 días.
- **Modo sin conexión:** `sw.js` guarda la app en el equipo (red primero para archivos propios); la caja guarda catálogo y una cola de ventas en IndexedDB y las envía con `registrar_venta_caja` al volver internet.

### Archivos

| Archivo | Qué hace |
|---|---|
| `index.html` | **Caja.** Lector USB (campo con foco que escucha Enter) o cámara, búsqueda por nombre/marca/color, cantidades, cliente, 4 formas de pago, descuento, cambio, recibo. Funciona sin conexión. |
| `cotizaciones.html` + `cotizacion.js` | Cotizaciones a cliente o prospecto, impresión/PDF, conversión en pedido. |
| `pedidos.html` | Pedidos de clientes: estados, entrega (registra la venta), cancelación. |
| `inventario.html` | Catálogo (productos y presentaciones, **venta por partes**, **% de ganancia**), entradas de mercancía (compra, inicial, ajuste), **importación** (pegar de Excel o CSV: reconoce lo existente por código/SKU, crea lo nuevo con marca y categoría, registra compra o inicial; avisa si la factura ya se cargó), filtro **Sin existencias** y **exportar para pedido** (CSV por último proveedor), clientes, etiquetas de código de barras. |
| `cartera.html` | Saldos por cliente, facturas con mora, abonos, recordatorio por WhatsApp (`wa.me`, antepone 57 a números de 10 dígitos). |
| `cierre.html` | **Cierre de caja.** Cubre desde el último cierre (uno o varios días acumulados): calcula lo que debería haber (base + ventas y abonos en efectivo − gastos y movimientos de socios de la caja, con correcciones si algo se anuló después de cerrar), conteo por total o por billetes y monedas, sobrante o faltante con nota obligatoria, base que queda y destino de lo retirado (cuenta, lo guarda un socio, caja fuerte, otro). Comprobante en la térmica. Historial; solo un socio anula, y solo el último. |
| `gastos.html` | Gastos (caja/cuenta/socio), gastos fijos del mes, foto de factura, retiros y reembolsos de socios. |
| `tablero.html` | Indicadores por período, ventas, margen, gastos y utilidad, top productos, reimpresión y anulación. |
| `catalogo.html` | **Público, sin sesión.** Productos publicados (`productos.publicado`) con foto, marca, categoría, código de color, presentaciones y partes, disponibilidad en palabras. **Sin precios.** Búsqueda, filtros, enlace por producto (`?p=id`). Lee solo `catalogo_publico()`. No va en `nav.js`. |
| `tarjeta-catalogo.html` | Tarjetas 9×5 cm (10 por hoja carta: frente negro con logo, reverso claro u oscuro con QR al catálogo público; mismas posiciones para imprimir a doble cara) o aviso de mostrador. Título y mensaje editables. Fuente Bebas Neue (como el logo). Sin sesión ni datos; se abre desde Inventario. |
| `usuarios.html` | Solo socios: lista de usuarios, invitar (Edge Function `invitar-usuario`), reenviar invitación, editar nombre/rol/activo. |
| `clave.html` | Recuperar contraseña (pide el enlace por correo), crearla desde la invitación o el enlace, y cambiarla con sesión. Sin barra de secciones. |
| `supabase/functions/invitar-usuario/index.ts` | Edge Function: comprueba `es_socio()` con la sesión de quien llama e invita con la llave de servicio (que vive en Supabase, nunca en la app). Se pega a mano en el editor de Edge Functions. |
| `supabase/README.md` | Pasos de configuración en Supabase: URL permitidas, función, SMTP propio (Gmail) y plantillas de correo en español. |
| `nav.js` | Barra de secciones común (íconos, sección actual, contador de pedidos con `navPendientes(db)`, que además muestra "Usuarios" solo a socios). Se oculta sin sesión. En celular (≤ 700 px) pasa abajo: Caja, Pedidos, Inventario, Cartera y "Más". Trae sus propios estilos (con `#nav`). También trae las **reglas comunes de celular** (≤ 700 px): tamaños compactos (campos y botones de 2.5rem, letra 15 px), diálogos como hoja inferior con el pie a la vista, y oculta la barra con el teclado abierto. La barra inferior mide unos 3.2rem: la barra de cobro de la caja y los pies fijos de cotizaciones y pedidos dependen de esa altura. |
| `recibo.js` | `imprimirRecibo(v)`: recibo térmico 58/80 mm en un iframe oculto. Comprobante interno, **no es factura electrónica**. |
| `etiquetas.js` | Códigos internos EAN-13 (`20` + id a 10 dígitos + dígito de control), SVG de etiquetas, impresión por driver. |
| `impresora-directa.js` | Impresión de etiquetas sin driver: Web Serial (puerto COM) o Web Bluetooth, ESC/POS raster. |
| `fotos.js` | Fotos de productos (10): URL pública, mapas `porProducto` / `porPresentacion`, `reducir` (800 px, WebP o JPEG), `subir`, `borrar`. Lo usan inventario, caja y cotizaciones. |
| `sw.js` | Service worker. **Al cambiar archivos que precachea, subir `VERSION`** (hoy `rebas-v18`). Guarda también las fotos de productos (guardado primero). El nombre debe ser `sw.js` en minúscula. |
| `config.js` | Configuración compartida (ver abajo). |
| `logo.svg`, `marca-rb.png`, `favicon-32.png`, `favicon-48.png`, `apple-touch-icon.png` | Marca. `marca-rb.png`: pistola blanca sobre negro, para piezas impresas. El logo cambia de color con el tema (estilo dentro del SVG). |
| `09_…sql` a `14_…sql` | Scripts de base de datos, en orden (ver abajo). Los 01 a 08 ya no están en el repo: 01–03 se recuperan del historial de git; 04–08 solo existen en Supabase. |
| `98_borrar_datos_prueba.sql`, `99_datos_prueba.sql`, `99_borrar_productos_por_codigo.sql` | Datos de prueba y limpieza. |
| `CONTEXTO_PROYECTO_Pinturas_Rebas.md` | Contexto antiguo (antes de 04). **Este `CLAUDE.md` lo reemplaza.** |

### `config.js` (no sobrescribir)

Define `window.APP_CONFIG` con `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `NOMBRE_TIENDA`, `NEGOCIO` (NIT, dirección, teléfono, pie del recibo) y `ANCHO_RECIBO` (`'58mm'` o `'80mm'`). Opcionales: `ANCHO_IMPRESION`, `PUNTOS_IMPRESORA_ETIQUETAS` (384 = 58 mm).

- **La copia de esta carpeta puede ser una plantilla** (`TU-PROYECTO`). La real, con las llaves, vive en el repo de GitHub. **Nunca reemplaces `config.js` del repo**; si hace falta un campo nuevo, di qué línea agregar a mano.
- La anon key es pública por diseño. **Nunca** poner la `service_role` ni ninguna llave secreta en el frontend ni en ningún archivo.

## Base de datos (Supabase)

### Reglas de seguridad (no romper)

- La protección real es **RLS** con `es_usuario_activo()` (usuario con fila activa en `perfiles`). El registro público de usuarios debe estar desactivado: los usuarios nuevos entran solo por invitación de un socio.
- Los formularios de ingreso llevan el enlace `<a class="olvide" href="clave.html">¿Olvidaste tu contraseña?</a>` (estilo en `nav.js`).
- Maestros (`categorias`, `marcas`, `proveedores`, `productos`, `presentaciones`, `clientes`): los usuarios activos leen y escriben directo.
- Transaccionales (`ventas`, `venta_detalle`, `movimientos_inventario`, `abonos`, `perfiles`, `pedidos`, `cotizaciones`, `gastos`, `movimientos_socios`…): **solo SELECT directo**. Toda escritura pasa por funciones `security definer`, con `revoke … from public, anon` y `grant … to authenticated`.
- Vistas con `security_invoker = true` para que respeten RLS.
- Storage: bucket privado `facturas-gastos` (5 MB, imágenes/PDF); se ve con URL firmada.

### Scripts, en orden de ejecución (SQL Editor del proyecto de la tienda)

1. `01_esquema_pinturas.sql`: tablas base, `v_catalogo`, `v_stock_bajo`, `registrar_venta`, `anular_venta`, `registrar_movimiento`, RLS, 9 categorías.
2. `02_cartera.sql`: cupo y plazo de clientes, `abonos`, `v_cartera_ventas`, `v_cartera_clientes`, trigger `validar_venta`, `registrar_abono`.
3. `03_tablero.sql`: `v_ventas_detalle` (descuento prorrateado y margen), `resumen_ventas`.
4. `04_pedidos.sql`: pedidos transaccionales, `guardar_pedido`, `cambiar_estado_pedido`, `v_pedidos`, `v_pedido_detalle`; la entrega usa `registrar_venta(..., p_pedido_id)`.
5. `05_cotizaciones.sql`: `cotizaciones`, `cotizacion_detalle`, vistas, `guardar_cotizacion`, `cambiar_estado_cotizacion`, `convertir_cotizacion`.
6. `06_ventas_sin_conexion.sql`: columnas de la caja en `ventas` (`uuid_caja`, `sin_conexion`, `revisar`…), `registrar_venta_caja` (idempotente por uuid), `v_ventas_revisar`, `marcar_venta_revisada`.
7. `07_gastos.sql`: `categorias_gasto`, `gastos_fijos`, `gastos`, `movimientos_socios`, vistas, funciones de registro y anulación, `resumen_gastos`, bucket de facturas.
8. `08_fracciones.sql`: **venta por partes** (ver abajo); reemplaza `v_catalogo`, `registrar_movimiento`, `registrar_venta` y `registrar_venta_caja`.
9. `09_mezclas.sql`: **venta completa** (ver abajo): tabla maestra `mezclas`. No reemplaza funciones.
10. `10_fotos_productos.sql`: `productos.imagen` (ruta en el bucket **público** `productos`, 1 MB, webp/jpeg/png) y políticas de Storage para usuarios activos. No reemplaza funciones ni vistas.
11. `11_usuarios.sql`: `es_socio()`, `listar_usuarios()` (con correo de `auth.users` y si la invitación está pendiente) y `actualizar_usuario()` (nadie se desactiva ni se quita el rol de socio a sí mismo). Las invitaciones van por la Edge Function.
12. `12_catalogo_publico.sql`: `productos.publicado` (por defecto no) y `catalogo_publico()` (`security definer`, ejecutable por `anon`): solo datos de vitrina, nunca precios, costos ni stock exacto. Se marca en el diálogo del producto en Inventario.
13. `13_ajuste_venta.sql`: **ajuste al total en la caja**: `ventas.recargo` y `ventas.ajuste_motivo`, y `registrar_venta_ajustada(p_venta, p_recargo, p_motivo)`, que llama a `registrar_venta_caja` (sin reemplazarla) y en la misma transacción guarda el motivo y suma el recargo al total. La caja la usa solo cuando hay descuento o recargo (motivo obligatorio, sale en el recibo).
14. `14_cierre_caja.sql`: **cierre de caja** (`cierre.html`): `cierres_caja`, `cierre_caja_detalle` (qué movimiento entró en qué cierre y por cuánto; así el siguiente toma solo lo que falta, incluidas ventas sin conexión que llegan tarde y anulaciones posteriores), `v_cierres_caja`, `caja_pendiente(p_desde)`, `registrar_cierre_caja(...)` (rechaza si entraron movimientos mientras se contaba) y `anular_cierre_caja` (solo socios, solo el último). El primer cierre empieza en una fecha elegida, con base conocida o "tomar lo contado como correcto". Lee `v_gastos` y `v_movimientos_socios` (07). No reemplaza funciones.

**Cambios de base de datos:** siempre en un **script nuevo numerado** (`09_…sql`), sin tocar los anteriores, con un encabezado que diga qué hace y después de cuál se ejecuta. Si un script reemplaza una función, copia la versión **más reciente** (hoy `registrar_venta*` y `registrar_movimiento` viven en `08`). Al reemplazar una vista, conserva las columnas en el mismo orden y agrega las nuevas al final.

> Ojo: el dueño tiene otros proyectos en la misma cuenta de Supabase (por ejemplo "Café del Dormilón"). Antes de pedirle que ejecute un script, recuérdale verificar que está en el proyecto de la tienda (el de `SUPABASE_URL`). Un error "relation … does not exist" suele ser eso.

### Modelo de datos (resumen)

- `productos` (referencia general, `codigo_color` de fábrica) → `presentaciones` (lo que se vende y se escanea: `sku`, `codigo_barras`, `precio_venta`, `costo`, `stock_minimo`, `activo`; único por `producto_id + nombre`).
- **El stock no se guarda:** se calcula sumando `movimientos_inventario` (kardex: `inicial`, `compra`, `venta`, `devolucion`, `ajuste`; + entra, − sale). Las cantidades son `numeric(12,2)`.
- `ventas` (`pagada`, `pendiente_pago`, `anulada`; `efectivo`, `transferencia`, `tarjeta`, `credito`) → `venta_detalle` (guarda `costo_unitario` para el margen).
- Precios: **siempre se toman de la base de datos**, nunca del navegador (excepto ventas sin conexión, que guardan el precio cobrado y quedan marcadas para revisar).

### Venta por partes (08)

- Una presentación puede ser parte de otra del mismo producto: `madre_id` + `fraccion` (0–1). Ej.: "1/36 de Galón" con `fraccion = 1/36`.
- Compras y stock inicial **solo en la madre**. Las partes no tienen entradas propias; sus ventas se registran como unidades enteras de la parte.
- `stock_vendible(id)` y `v_catalogo.stock`: madre = galones cerrados; parte = cuántas alcanzan con galones cerrados + lo que queda del abierto. `v_catalogo` agrega al final `madre_id`, `fraccion`, `abierto` (fracción que queda del tarro abierto) y `tiene_fracciones`.
- El costo de la parte lo pone un trigger: costo de la madre × fracción, y se actualiza cuando cambia el de la madre.

### Venta completa: producto + catalizador (09)

- `mezclas` (maestro): `presentacion_id` (producto, presentación completa, única), `catalizador_id` (presentación completa) y `proporcion` = unidades del catalizador por unidad del producto. Ej.: Galón de poliuretano → 1/4 de Galón de catalizador = `0.25`. Se configura en Inventario › Mezclas, que muestra qué parte del catalizador corresponde a cada medida y cuál falta crear.
- La regla de la completa aplica a sus partes. La caja calcula lo necesario (medida × proporción × cantidad) y elige la presentación del catalizador (completa o parte) que lo da exacto con menos envases (tolerancia 2 %). La agrega como otro ítem de la venta (precio y stock propios); sin parte exacta, no deja cobrar el completo.
- Por defecto el producto entra completo; en la línea se puede vender sin catalizador. Las reglas se guardan en IndexedDB para vender sin conexión. `elegirCatalizador` está igual en `index.html` e `inventario.html`.

### Fotos de productos (10)

Una foto por producto; todas sus presentaciones y partes la muestran. Se elige en el diálogo del producto, se reduce en el navegador y se sube al guardar, con nombre nuevo (`producto_id/fecha.webp`) para que nunca quede vieja en caché; la anterior se borra. Se ve en el catálogo de Inventario, en la caja (resultados y líneas; el mapa se guarda en IndexedDB como `fotos` y `sw.js` guarda las imágenes) y en cotizaciones (pantalla e impresión carta, no el ticket). Las `<img>` de fotos llevan `crossorigin="anonymous"`. Sin el script 10, las pantallas siguen funcionando sin fotos.

### % de ganancia (inventario.html)

No se guarda en la base de datos: se deduce de precio y costo. Precio = costo × (1 + %/100), **redondeado hacia arriba a $100**. Aplica a presentaciones y partes; en Entradas, una compra puede actualizar el precio con el % (y las partes con el suyo). El último % usado se recuerda en `localStorage` (`rebas-ganancia`).

## Convenciones de código

- Antes de cambiar una pantalla, léela: todas comparten estilos, el patrón de login, la barra de navegación y el encabezado con logo. La barra la dibuja `nav.js` (`<nav class="nav" id="nav" aria-label="Secciones"></nav><script src="nav.js?v=7"></script>`); una pantalla nueva se agrega en `SECCIONES` de `nav.js` y cada pantalla llama `navPendientes(db)` al iniciar sesión.
- Estados con un solo código: `.estado` + `.estado-pendiente` (`--aviso`), `.estado-confirmado` (`--acento`), `.estado-ok` (`--ok`), `.estado-mal` (`--alerta`), `.estado-neutro` (`--suave`); siempre con la palabra, y en alertas con ícono. Un solo botón primario por panel, alto mínimo 2.75rem.
- Barras de desplazamiento: todas (diálogos, listas, tablas) con el mismo estilo que la de la ventana, según el tema. Cada página declara `color-scheme: light dark` en `:root`; no poner barras con colores propios.
- `esc()` para todo lo que se inserte en HTML. Nada de `innerHTML` con datos sin escapar.
- `onAuthStateChange` con `setTimeout(..., 0)`: no consultar dentro del callback.
- Los formularios donde se escanea evitan que el Enter del lector los envíe.
- Errores de negocio en español y entendibles; mostrar `error.message` de las funciones SQL.
- Diseño: tema claro y oscuro automático (`prefers-color-scheme`), fuentes Barlow y Barlow Condensed, acento azul petróleo `#0E5266`, gris primer `#E3E4E1`, amarillo cinta `#E8D08A` en el campo del lector. Sin degradados ni tarjetas decorativas. Debe verse bien en celular (≤ 700 px).
- `localStorage` solo para comodidades por equipo (medida de etiqueta, último %…), nunca para datos del negocio.
- Al cambiar un `.js` que se carga con `?v=`, sube ese número en las páginas que lo usan para evitar caché vieja.

## Cómo verificar antes de entregar

- JavaScript: extrae los `<script>` de cada HTML y pásalos por `node --check`; los `.js` directamente.
- SQL: si hay Postgres local, crea una base vacía, carga un stub de `auth` (`auth.users`, `auth.uid()` leyendo `current_setting('test.uid')`), ejecuta 01→08 y el script nuevo, y prueba como `set role authenticated` (dando antes los permisos que Supabase da a `authenticated`). Prueba también los casos que deben fallar.
- Al terminar, di con claridad **qué archivos subir al repo** (GitHub > Add file > Upload files, o `git push`) y **qué script ejecutar en Supabase**. Después de publicar, recargar con Ctrl + F5.

## Hardware de la tienda

- Recibos: impresora térmica **Jaltech JAL 801** de 58 mm, en Windows como **POS-58** (USB001). La hoja del recibo se ajusta al alto del contenido (`@page size: ancho alto`) para no botar papel.
- Etiquetas: **DigitalPOS DIG-M220** (58 mm, sensor de separación, protocolo tipo Phomemo M220), emparejada por Bluetooth en Windows sin driver; se imprime por **puerto COM (Web Serial)** desde Chrome/Edge. Cada etiqueta va en una sola imagen GS v 0 con cabecera `1b 4e 0d 05 1b 4e 04 0a 1f 11 0a` y cierre `1f f0 05 00 1f f0 03 00`, todo en una sola escritura. No mandar recibos a esta impresora.
- Lector de código de barras USB (actúa como teclado).

## Pendientes conocidos

- Confirmar que el registro público de usuarios está desactivado y configurar el respaldo en el repo privado.
- Factura electrónica DIAN: el recibo no la reemplaza; revisar con contador.
- Etiquetas: ajuste vertical si la medida real de la etiqueta no coincide con la elegida.
- Ideas sin construir: panel de uso del plan gratuito de Supabase, Power BI con rol de solo lectura.
