# Todo Pinturas RB: app de caja, inventario y cartera

Claude Code lee este archivo al abrir la carpeta. Responde **siempre en español** (interfaz, mensajes de error, comentarios y textos para el usuario).

## Qué es

Tienda de **pintura automotriz y accesorios** en Medellín, con tres socios. Antes se llamaba "Pinturas Rebas"; el nombre visible sale de `NOMBRE_TIENDA` en `config.js`. La app cubre caja (ventas con lector de código de barras), cotizaciones, pedidos, inventario, cartera (crédito y abonos), gastos y tablero. Todo con opciones gratuitas.

- Moneda: pesos colombianos (COP), sin decimales en pantalla (`Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 })`).
- Zona horaria: `America/Bogota`. Los cortes de día y los vencimientos se calculan en esa zona, no en UTC.
- Usuarios: solo los tres socios, cada uno con fila en `perfiles`.

## Arquitectura

- **Frontend:** HTML, CSS y JavaScript puros, **sin build ni npm**. Un archivo por pantalla. Publicado en GitHub Pages desde el repo público `Guiral97/PinturasRebas` (rama `main`) → `https://guiral97.github.io/PinturasRebas/`.
- **Librerías por CDN** (no agregar otras sin necesidad): `@supabase/supabase-js@2` (jsDelivr), `html5-qrcode@2.3.8` (cámara), `chart.js@4.4.1` (tablero).
- **Backend:** Supabase plan gratuito (Postgres + Auth + Storage). Límites: 500 MB de base de datos, 1 GB de Storage, 5 GB de transferencia al mes, el proyecto se pausa tras 7 días sin uso, sin respaldos automáticos.
- **Respaldo:** GitHub Action diaria (`respaldo-diario.yml`) en un repo **privado aparte**: consulta la API (evita la pausa) y guarda un volcado 60 días.
- **Modo sin conexión:** `sw.js` guarda la app en el equipo (red primero para archivos propios); la caja guarda catálogo y una cola de ventas en IndexedDB y las envía con `registrar_venta_caja` al volver internet.

### Archivos

| Archivo | Qué hace |
|---|---|
| `index.html` | **Caja.** Lector USB (campo con foco que escucha Enter) o cámara, búsqueda por nombre/marca/color, cantidades, cliente, 4 formas de pago, descuento, cambio, recibo. Funciona sin conexión. |
| `cotizaciones.html` + `cotizacion.js` | Cotizaciones a cliente o prospecto, impresión/PDF, conversión en pedido. |
| `pedidos.html` | Pedidos de clientes: estados, entrega (registra la venta), cancelación. |
| `inventario.html` | Catálogo (productos y presentaciones, **venta por partes**, **% de ganancia**), entradas de mercancía (compra, inicial, ajuste), clientes, etiquetas de código de barras. |
| `cartera.html` | Saldos por cliente, facturas con mora, abonos, recordatorio por WhatsApp (`wa.me`, antepone 57 a números de 10 dígitos). |
| `gastos.html` | Gastos (caja/cuenta/socio), gastos fijos del mes, foto de factura, retiros y reembolsos de socios. |
| `tablero.html` | Indicadores por período, ventas, margen, gastos y utilidad, top productos, reimpresión y anulación. |
| `nav.js` | Barra de secciones común (íconos, sección actual, contador de pedidos con `navPendientes(db)`). En celular (≤ 700 px) pasa abajo: Caja, Pedidos, Inventario, Cartera y "Más". Trae sus propios estilos (con `#nav`). |
| `recibo.js` | `imprimirRecibo(v)`: recibo térmico 58/80 mm en un iframe oculto. Comprobante interno, **no es factura electrónica**. |
| `etiquetas.js` | Códigos internos EAN-13 (`20` + id a 10 dígitos + dígito de control), SVG de etiquetas, impresión por driver. |
| `impresora-directa.js` | Impresión de etiquetas sin driver: Web Serial (puerto COM) o Web Bluetooth, ESC/POS raster. |
| `sw.js` | Service worker. **Al cambiar archivos que precachea, subir `VERSION`** (hoy `rebas-v11`). El nombre debe ser `sw.js` en minúscula. |
| `config.js` | Configuración compartida (ver abajo). |
| `logo.svg`, `favicon-32.png`, `favicon-48.png`, `apple-touch-icon.png` | Marca. El logo cambia de color con el tema (estilo dentro del SVG). |
| `01_…sql` a `09_…sql` | Scripts de base de datos, en orden (ver abajo). |
| `98_borrar_datos_prueba.sql`, `99_datos_prueba.sql`, `99_borrar_productos_por_codigo.sql` | Datos de prueba y limpieza. |
| `CONTEXTO_PROYECTO_Pinturas_Rebas.md` | Contexto antiguo (antes de 04). **Este `CLAUDE.md` lo reemplaza.** |

### `config.js` (no sobrescribir)

Define `window.APP_CONFIG` con `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `NOMBRE_TIENDA`, `NEGOCIO` (NIT, dirección, teléfono, pie del recibo) y `ANCHO_RECIBO` (`'58mm'` o `'80mm'`). Opcionales: `ANCHO_IMPRESION`, `PUNTOS_IMPRESORA_ETIQUETAS` (384 = 58 mm).

- **La copia de esta carpeta puede ser una plantilla** (`TU-PROYECTO`). La real, con las llaves, vive en el repo de GitHub. **Nunca reemplaces `config.js` del repo**; si hace falta un campo nuevo, di qué línea agregar a mano.
- La anon key es pública por diseño. **Nunca** poner la `service_role` ni ninguna llave secreta en el frontend ni en ningún archivo.

## Base de datos (Supabase)

### Reglas de seguridad (no romper)

- La protección real es **RLS** con `es_usuario_activo()` (usuario con fila activa en `perfiles`). El registro público de usuarios debe estar desactivado.
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

### % de ganancia (inventario.html)

No se guarda en la base de datos: se deduce de precio y costo. Precio = costo × (1 + %/100), **redondeado hacia arriba a $100**. Aplica a presentaciones y partes; en Entradas, una compra puede actualizar el precio con el % (y las partes con el suyo). El último % usado se recuerda en `localStorage` (`rebas-ganancia`).

## Convenciones de código

- Antes de cambiar una pantalla, léela: todas comparten estilos, el patrón de login, la barra de navegación y el encabezado con logo. La barra la dibuja `nav.js` (`<nav class="nav" id="nav" aria-label="Secciones"></nav><script src="nav.js?v=3"></script>`); una pantalla nueva se agrega en `SECCIONES` de `nav.js` y cada pantalla llama `navPendientes(db)` al iniciar sesión.
- Estados con un solo código: `.estado` + `.estado-pendiente` (`--aviso`), `.estado-confirmado` (`--acento`), `.estado-ok` (`--ok`), `.estado-mal` (`--alerta`), `.estado-neutro` (`--suave`); siempre con la palabra, y en alertas con ícono. Un solo botón primario por panel, alto mínimo 2.75rem.
- Desplazamiento: siempre con la barra del borde derecho de la ventana, nunca una barra interna en paneles o diálogos. Un diálogo largo ocupa toda la ventana con fondo transparente y se desplaza él; la caja visible es su `form` (ver `inventario.html`).
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
- Ideas sin construir: cierre de caja diario, importación masiva de productos (Excel/CSV), panel de uso del plan gratuito de Supabase, Power BI con rol de solo lectura.
