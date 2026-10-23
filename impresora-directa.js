// Impresión directa (sin driver de Windows) en impresoras térmicas de 58 mm
// como la DigitalPOS DIG-M220. Dos caminos, los dos desde Chrome o Edge:
//
//  - Bluetooth: Web Bluetooth (BLE). Funciona en PC y en celulares Android.
//  - Puerto COM: Web Serial. Sirve cuando la impresora ya está emparejada por
//    Bluetooth en Windows (crea un puerto COM "saliente") o conectada por un
//    cable que aparezca como puerto serie.
//
// Envía comandos ESC/POS: la etiqueta se dibuja como imagen en blanco y negro
// (GS v 0) a 8 puntos por mm, el ancho del cabezal de 58 mm es 384 puntos.
// Requiere etiquetas.js (svgCodigo, anchoUtil).
(function () {
  const PUNTOS_MM = 8;
  const cfg = window.APP_CONFIG || {};
  const PUNTOS_CABEZAL = Number(cfg.PUNTOS_IMPRESORA_ETIQUETAS) || 384;   // 58 mm -> 384, 80 mm -> 576

  // Servicios BLE que usan las impresoras térmicas chinas más comunes
  const SERVICIOS = [
    '0000ff00-0000-1000-8000-00805f9b34fb',   // Phomemo / DIG-M220
    '000018f0-0000-1000-8000-00805f9b34fb',
    '0000ae30-0000-1000-8000-00805f9b34fb',
    '0000fee7-0000-1000-8000-00805f9b34fb',
    '0000ffe0-0000-1000-8000-00805f9b34fb',
    '0000ff80-0000-1000-8000-00805f9b34fb',
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2'
  ];

  const espera = (ms) => new Promise((r) => setTimeout(r, ms));
  const soportaBluetooth = () => !!(navigator.bluetooth && navigator.bluetooth.requestDevice);
  // En Android, Web Serial solo ve impresoras Bluetooth clásicas emparejadas; la
  // DIG-M220 llega al celular por BLE, así que allí se usa el botón "Bluetooth"
  const esAndroid = () => /Android/i.test(navigator.userAgent);
  const soportaSerial = () => !!(navigator.serial && navigator.serial.requestPort) && !esAndroid();

  // ---------- Dibujo de la etiqueta ----------
  function cargarImagen(svg) {
    return new Promise((ok, mal) => {
      const img = new Image();
      img.onload = () => ok(img);
      img.onerror = () => mal(new Error('No se pudo dibujar la etiqueta'));
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    });
  }

  // Devuelve un canvas del ancho del cabezal con la etiqueta centrada
  async function canvasEtiqueta(codigo, { ancho = 58, alto = 30 } = {}, contenido = {}) {
    const anchoCabezalMm = PUNTOS_CABEZAL / PUNTOS_MM;
    const util = Math.min(window.anchoUtil(ancho), anchoCabezalMm);
    const margenV = 1.5;
    const r = window.svgEtiqueta(codigo, { anchoMm: util, altoMm: alto - 2 * margenV, ...contenido });
    if (!r.cabe) throw new Error('El contenido no cabe en esa etiqueta');
    const img = await cargarImagen(r.svg);

    const c = document.createElement('canvas');
    c.width = PUNTOS_CABEZAL;
    c.height = Math.round(alto * PUNTOS_MM);
    const g = c.getContext('2d');
    g.fillStyle = '#fff';
    g.fillRect(0, 0, c.width, c.height);
    const w = Math.round(r.ancho * PUNTOS_MM), h = Math.round((alto - 2 * margenV) * PUNTOS_MM);
    g.imageSmoothingEnabled = false;
    g.drawImage(img, Math.round((c.width - w) / 2), Math.round(margenV * PUNTOS_MM), w, h);
    return c;
  }

  // Canvas -> bytes ESC/POS (GS v 0)
  function rasterEscPos(canvas) {
    const { width, height } = canvas;
    const px = canvas.getContext('2d').getImageData(0, 0, width, height).data;
    const bytesFila = Math.ceil(width / 8);
    const partes = [];
    // Una sola imagen por etiqueta. Las impresoras de etiquetas con sensor de
    // separación (como la DIG-M220) toman cada imagen como una etiqueta y saltan a
    // la siguiente: si se manda en franjas, cada franja cae en una etiqueta distinta.
    const ALTO_FRANJA = 0xffff;
    for (let y0 = 0; y0 < height; y0 += ALTO_FRANJA) {
      const filas = Math.min(ALTO_FRANJA, height - y0);
      const cab = [0x1d, 0x76, 0x30, 0x00, bytesFila & 0xff, bytesFila >> 8, filas & 0xff, filas >> 8];
      const datos = new Uint8Array(bytesFila * filas);
      for (let y = 0; y < filas; y++) {
        for (let x = 0; x < width; x++) {
          const i = ((y0 + y) * width + x) * 4;
          const luz = px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114;
          if (px[i + 3] > 127 && luz < 140) datos[y * bytesFila + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
      partes.push(new Uint8Array(cab), datos);
    }
    return partes;
  }

  function unir(partes) {
    const total = partes.reduce((s, p) => s + p.length, 0);
    const out = new Uint8Array(total);
    let o = 0;
    for (const p of partes) { out.set(p, o); o += p.length; }
    return out;
  }

  // Rollo continuo (58/80 mm) o etiquetas troqueladas con separación
  const esContinuo = (medida) => Number(medida?.ancho) === 58 || Number(medida?.ancho) === 80;

  async function bytesEtiquetas(codigo, cantidad, medida, contenido = {}) {
    const una = unir(rasterEscPos(await canvasEtiqueta(codigo, medida, contenido)));
    const partes = [new Uint8Array([0x1b, 0x40])];               // ESC @: reiniciar
    if (esContinuo(medida)) {
      for (let i = 0; i < cantidad; i++) partes.push(una);
      partes.push(new Uint8Array([0x1b, 0x64, 0x04]));           // ESC d 4: avanzar para cortar
      return unir(partes);
    }
    // Etiquetas troqueladas (DIG-M220 / Phomemo M220 y similares): cada etiqueta va
    // completa entre una cabecera (tipo de papel: con separación) y un cierre que
    // le dice a la impresora que la etiqueta terminó. Sin esto, imprime por pedazos
    // y salta a la siguiente etiqueta con cada pedazo que le llega.
    const cabecera = new Uint8Array([
      0x1b, 0x4e, 0x0d, 0x05,     // velocidad
      0x1b, 0x4e, 0x04, 0x0a,     // oscuridad
      0x1f, 0x11, 0x0a            // papel: etiquetas con separación
    ]);
    const cierre = new Uint8Array([0x1f, 0xf0, 0x05, 0x00, 0x1f, 0xf0, 0x03, 0x00]);
    for (let i = 0; i < cantidad; i++) partes.push(cabecera, una, cierre);
    return unir(partes);
  }

  // ---------- Conexión ----------
  let conexion = null;   // { tipo: 'ble'|'serial', nombre, enviar(bytes), cerrar() }

  // Canales de impresión conocidos, del más probable al menos probable
  const CANALES_PREFERIDOS = ['0000ff02', '0000ae01', '0000ffe1', '49535343-8841', 'bef8d6c9', '0000ff01'];
  const prioridad = (c) => {
    const i = CANALES_PREFERIDOS.findIndex((p) => c.uuid.startsWith(p));
    return (i < 0 ? CANALES_PREFERIDOS.length : i) * 2 + (c.properties.writeWithoutResponse ? 0 : 1);
  };
  const corto = (c) => (c.uuid.startsWith('0000') ? c.uuid.slice(4, 8) : c.uuid.slice(0, 8));

  // Canal que funcionó con cada impresora (comodidad de este equipo)
  function leerCanales() {
    try { return JSON.parse(localStorage.getItem('rebas-ble-canal') || '{}'); } catch (_) { return {}; }
  }
  function guardarCanal(nombre, uuid) {
    try { localStorage.setItem('rebas-ble-canal', JSON.stringify({ ...leerCanales(), [nombre]: uuid })); } catch (_) {}
  }

  async function conectarBluetooth() {
    const dispositivo = await navigator.bluetooth.requestDevice({
      acceptAllDevices: true,
      optionalServices: SERVICIOS
    });
    const gatt = await dispositivo.gatt.connect();
    const nombreEquipo = dispositivo.name || 'Impresora Bluetooth';
    // Todos los canales donde se puede escribir. Muchas impresoras tienen varios y
    // solo uno imprime: en los demás los datos se aceptan y se pierden sin error.
    const canales = [];
    for (const uuid of SERVICIOS) {
      let servicio;
      try { servicio = await gatt.getPrimaryService(uuid); } catch (_) { continue; }
      let cars = [];
      try { cars = await servicio.getCharacteristics(); } catch (_) { continue; }
      for (const c of cars) {
        if (c.properties.writeWithoutResponse || c.properties.write) canales.push(c);
        // Algunas impresoras no aceptan datos hasta que alguien escucha sus avisos
        if (c.properties.notify) { try { await c.startNotifications(); } catch (_) {} }
      }
    }
    if (!canales.length) {
      gatt.disconnect();
      throw new Error(`"${nombreEquipo}" se conectó, pero no tiene un canal de impresión conocido. Prueba con "Puerto COM".`);
    }
    canales.sort((a, b) => prioridad(a) - prioridad(b));
    const guardado = leerCanales()[nombreEquipo];
    let indice = Math.max(0, canales.findIndex((c) => c.uuid === guardado));
    let car = canales[indice];

    // Bytes por envío; si la impresora no lo acepta se baja a 20. Android corta en
    // silencio los envíos sin respuesta a 20 bytes y la imagen llega incompleta.
    let tam = esAndroid() ? 20 : 180;
    const sinRespuesta = () => car.properties.writeWithoutResponse;
    async function escribir(trozo) {
      if (sinRespuesta()) await car.writeValueWithoutResponse(trozo);
      else await car.writeValueWithResponse(trozo);
    }
    return {
      tipo: 'ble',
      get nombre() { return `${nombreEquipo} (canal ${corto(car)})`; },
      get canal() { return { numero: indice + 1, total: canales.length }; },
      // Pasa al siguiente canal y lo recuerda para la próxima vez
      otroCanal() {
        indice = (indice + 1) % canales.length;
        car = canales[indice];
        guardarCanal(nombreEquipo, car.uuid);
      },
      async enviar(bytes, progreso) {
        if (!dispositivo.gatt.connected) await dispositivo.gatt.connect();
        for (let i = 0; i < bytes.length; ) {
          const trozo = bytes.subarray(i, i + tam);
          try {
            await escribir(trozo);
          } catch (e) {
            if (tam > 20) { tam = 20; continue; }   // reintentar el mismo trozo más pequeño
            throw e;
          }
          i += trozo.length;
          progreso?.(i / bytes.length);
          // Pausa corta para no llenar la memoria de la impresora
          if (sinRespuesta()) await espera(tam > 20 ? 4 : 2);
        }
      },
      cerrar() { try { dispositivo.gatt.disconnect(); } catch (_) {} }
    };
  }

  async function conectarSerial() {
    const puertos = await navigator.serial.getPorts();
    const puerto = puertos.length === 1 ? puertos[0] : await navigator.serial.requestPort();
    if (!puerto.readable) await puerto.open({ baudRate: 9600 });
    return {
      tipo: 'serial',
      nombre: 'Puerto COM',
      async enviar(bytes, progreso) {
        const w = puerto.writable.getWriter();
        try {
          // Todo de una vez: si llega por pedazos con pausas, la impresora de
          // etiquetas imprime cada pedazo en una etiqueta distinta
          progreso?.(0.1);
          await w.write(bytes);
          progreso?.(1);
        } finally { w.releaseLock(); }
      },
      async cerrar() { try { await puerto.close(); } catch (_) {} }
    };
  }

  async function conectar(tipo) {
    if (conexion && conexion.tipo === tipo) return conexion;
    if (conexion) await conexion.cerrar();
    conexion = null;
    if (tipo === 'ble') {
      if (!soportaBluetooth()) throw new Error('Este navegador no permite Bluetooth. Usa Chrome o Edge.');
      conexion = await conectarBluetooth();
    } else {
      if (!soportaSerial()) throw new Error('Este navegador no permite puertos COM. Usa Chrome o Edge en el computador.');
      conexion = await conectarSerial();
    }
    return conexion;
  }

  async function imprimirDirecto(tipo, codigo, cantidad, medida, progreso, contenido = {}) {
    const c = await conectar(tipo);   // primero: el navegador exige que el clic sea reciente
    const bytes = await bytesEtiquetas(codigo, cantidad, medida, contenido);
    try {
      await c.enviar(bytes, progreso);
    } catch (e) {
      await c.cerrar();
      conexion = null;
      throw e;
    }
    return c.nombre;
  }

  // Mensaje entendible para los errores del navegador
  function errorDirecto(e) {
    const n = e && e.name;
    if (n === 'NotFoundError') return 'No se eligió ninguna impresora.';
    if (n === 'SecurityError') return 'El navegador bloqueó el acceso. Abre la app desde su dirección https.';
    if (n === 'NetworkError') return 'Se perdió la conexión con la impresora. Revisa que esté encendida y cerca.';
    if (n === 'InvalidStateError') return 'El puerto ya está en uso por otro programa. Ciérralo e intenta de nuevo.';
    return e?.message || String(e);
  }

  Object.assign(window, {
    impresoraDirecta: { conectar, soportaBluetooth, soportaSerial, imprimirDirecto, bytesEtiquetas, canvasEtiqueta, errorDirecto,
      conectada: () => conexion && { tipo: conexion.tipo, nombre: conexion.nombre, canal: conexion.canal },
      // Bluetooth con varios canales: cambia al siguiente (el que imprime varía según el modelo)
      otroCanal: () => { if (conexion?.otroCanal) conexion.otroCanal(); return conexion?.nombre; } }
  });
})();