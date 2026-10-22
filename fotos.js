// Fotos de productos (10_fotos_productos.sql): una por producto, en el bucket
// público "productos". La ruta se guarda en productos.imagen; cada foto nueva
// lleva un nombre distinto, así el navegador puede guardarla sin miedo a que cambie.
(function () {
  const cfg = window.APP_CONFIG || {};
  const BUCKET = 'productos';
  const LADO = 800;   // px del lado mayor: suficiente para verla y liviana para el Storage gratuito

  const url = (ruta) => (ruta
    ? `${cfg.SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${String(ruta).split('/').map(encodeURIComponent).join('/')}`
    : '');

  // Trae todas las filas de a 1000 (el límite de Supabase por consulta)
  async function todas(consulta) {
    const filas = [];
    for (let desde = 0; ; desde += 1000) {
      const { data, error } = await consulta().range(desde, desde + 999);
      if (error) return null;   // por ejemplo, si 10_fotos_productos.sql aún no se ejecutó
      filas.push(...data);
      if (data.length < 1000) return filas;
    }
  }

  // { producto_id: url }
  async function porProducto(db) {
    const filas = await todas(() => db.from('productos').select('id, imagen').not('imagen', 'is', null).order('id'));
    return filas && Object.fromEntries(filas.map((p) => [p.id, url(p.imagen)]));
  }

  // { presentacion_id: url }: para la caja y las cotizaciones, que trabajan con presentaciones
  async function porPresentacion(db) {
    const filas = await todas(() => db.from('presentaciones').select('id, productos!inner(imagen)')
      .not('productos.imagen', 'is', null).order('id'));
    return filas && Object.fromEntries(filas.map((p) => [p.id, url(p.productos.imagen)]));
  }

  // Reduce la foto (la del celular pesa varios MB) a WebP o JPEG de LADO px
  function reducir(archivo) {
    return new Promise((ok, mal) => {
      const img = new Image();
      const src = URL.createObjectURL(archivo);
      img.onload = () => {
        URL.revokeObjectURL(src);
        const k = Math.min(1, LADO / Math.max(img.naturalWidth, img.naturalHeight));
        const c = document.createElement('canvas');
        c.width = Math.round(img.naturalWidth * k);
        c.height = Math.round(img.naturalHeight * k);
        const g = c.getContext('2d');
        g.fillStyle = '#fff';   // las PNG transparentes quedan sobre blanco
        g.fillRect(0, 0, c.width, c.height);
        g.drawImage(img, 0, 0, c.width, c.height);
        // Safari no siempre sabe hacer WebP: devuelve PNG, y entonces se usa JPEG
        c.toBlob((b) => {
          if (b && b.type === 'image/webp') return ok(b);
          c.toBlob((j) => (j ? ok(j) : mal(new Error('No se pudo preparar la foto.'))), 'image/jpeg', 0.82);
        }, 'image/webp', 0.8);
      };
      img.onerror = () => { URL.revokeObjectURL(src); mal(new Error('Ese archivo no es una imagen que el navegador pueda abrir. Prueba con una foto JPG o PNG.')); };
      img.src = src;
    });
  }

  // Sube la foto ya reducida y devuelve su ruta
  async function subir(db, productoId, blob) {
    const ruta = `${productoId}/${Date.now()}.${blob.type === 'image/webp' ? 'webp' : 'jpg'}`;
    const { error } = await db.storage.from(BUCKET).upload(ruta, blob, { contentType: blob.type, cacheControl: '31536000' });
    if (error) throw new Error(/bucket/i.test(error.message)
      ? 'Falta ejecutar 10_fotos_productos.sql en Supabase para guardar fotos.'
      : 'No se pudo subir la foto: ' + error.message);
    return ruta;
  }

  async function borrar(db, ruta) {
    if (ruta) await db.storage.from(BUCKET).remove([ruta]);
  }

  window.fotosProductos = { url, porProducto, porPresentacion, reducir, subir, borrar };
})();
