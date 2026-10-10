// Etiquetas de código de barras para la impresora de etiquetas (DIG-M220 u otra).
//
// Códigos propios: EAN-13 que empiezan por "20". Ese rango está reservado
// para uso interno de cada tienda, así que nunca choca con un código de
// fábrica. Se arma con el id de la presentación: 20 + id (10 dígitos) + dígito
// de control. Ej.: presentación 57 -> 2000000000572.
//
// Uso:
//   codigoInterno(57)                      -> '2000000000572'
//   imprimirEtiquetas('2000000000572', 10, { ancho: 40, alto: 30 })
//   svgCodigo('2000000000572', { anchoMm: 32, altoMm: 16 })  (vista previa)
(function () {
  const L = ['0001101', '0011001', '0010011', '0111101', '0100011', '0110001', '0101111', '0111011', '0110111', '0001011'];
  const G = ['0100111', '0110011', '0011011', '0100001', '0011101', '0111001', '0000101', '0010001', '0001001', '0010111'];
  const R = ['1110010', '1100110', '1101100', '1000010', '1011100', '1001110', '1010000', '1000100', '1001000', '1110100'];
  const PARIDAD = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL'];

  const PUNTOS_MM = 8;          // cabezal de 203 dpi
  const MODULOS = 95;           // ancho de un EAN-13 sin márgenes
  const MARGEN_IZQ = 11, MARGEN_DER = 7;   // zonas en blanco que pide el lector

  function digitoControl(doce) {
    let s = 0;
    for (let i = 0; i < 12; i++) s += Number(doce[i]) * (i % 2 ? 3 : 1);
    return String((10 - (s % 10)) % 10);
  }

  const esEan13 = (c) => /^\d{13}$/.test(c) && digitoControl(c.slice(0, 12)) === c[12];
  const esInterno = (c) => esEan13(c) && c.startsWith('20');

  function codigoInterno(id) {
    const n = String(Math.trunc(Number(id)));
    if (!/^\d{1,10}$/.test(n) || n === '0') throw new Error('Id de presentación no válido');
    const doce = '20' + n.padStart(10, '0');
    return doce + digitoControl(doce);
  }

  // Cadena de 95 módulos (1 = barra)
  function modulosEan13(c) {
    const p = PARIDAD[Number(c[0])];
    let m = '101';
    for (let i = 1; i <= 6; i++) m += (p[i - 1] === 'L' ? L : G)[Number(c[i])];
    m += '01010';
    for (let i = 7; i <= 12; i++) m += R[Number(c[i])];
    return m + '101';
  }

  // Code 128-B para códigos que no son EAN-13 (SKU, códigos de fábrica raros)
  const C128 = ['212222','222122','222221','121223','121322','131222','122213','122312','132212','221213','221312','231212','112232','122132','122231','113222','123122','123221','223211','221132','221231','213212','223112','312131','311222','321122','321221','312212','322112','322211','212123','212321','232121','111323','131123','131321','112313','132113','132311','211313','231113','231311','112133','112331','132131','113123','113321','133121','313121','211331','231131','213113','213311','213131','311123','311321','331121','312113','312311','332111','314111','221411','431111','111224','111422','121124','121421','141122','141221','112214','112412','122114','122411','142112','142211','241211','221114','413111','241112','134111','111242','121142','121241','114212','124112','124211','411212','421112','421211','212141','214121','412121','111143','111341','131141','114113','114311','411113','411311','113141','114131','311141','411131','211412','211214','211232','2331112'];
  function modulos128(texto) {
    const valores = [104];
    for (const ch of texto) {
      const v = ch.charCodeAt(0) - 32;
      if (v < 0 || v > 94) throw new Error('El código tiene caracteres que no se pueden imprimir');
      valores.push(v);
    }
    let suma = valores[0];
    for (let i = 1; i < valores.length; i++) suma += valores[i] * i;
    valores.push(suma % 103, 106);
    let m = '';
    for (const v of valores) {
      [...C128[v]].forEach((anchoBarra, k) => { m += (k % 2 ? '0' : '1').repeat(Number(anchoBarra)); });
    }
    return m;
  }

  function modulosDe(codigo) {
    return esEan13(codigo)
      ? { m: modulosEan13(codigo), izq: MARGEN_IZQ, der: MARGEN_DER, ean: true }
      : { m: modulos128(codigo), izq: 10, der: 10, ean: false };
  }

  // Ancho de cada barra en puntos enteros de la impresora: así sale nítido
  function puntosPorModulo(totalModulos, anchoMm) {
    return Math.max(2, Math.min(4, Math.floor((anchoMm * PUNTOS_MM) / totalModulos)));
  }

  // SVG en milímetros. Devuelve también el ancho real para centrarlo.
  function svgCodigo(codigo, { anchoMm, altoMm, texto = true }) {
    const { m, izq, der, ean } = modulosDe(codigo);
    const total = izq + m.length + der;
    const pm = puntosPorModulo(total, anchoMm);
    const u = pm / PUNTOS_MM;                         // mm por módulo
    const ancho = total * u;
    const altoTexto = texto ? Math.min(3.2, altoMm * 0.22) : 0;
    const altoBarras = altoMm - altoTexto - (texto ? 0.6 : 0);

    let barras = '';
    for (let i = 0; i < m.length; ) {
      if (m[i] === '1') {
        let j = i;
        while (m[j] === '1') j++;
        const x = (izq + i) * u;
        barras += `<rect x="${x.toFixed(3)}" y="0" width="${((j - i) * u).toFixed(3)}" height="${altoBarras.toFixed(3)}"/>`;
        i = j;
      } else i++;
    }

    let numeros = '';
    if (texto) {
      const y = altoMm - 0.2;
      const fs = altoTexto.toFixed(2);
      if (ean) {
        // Forma clásica: primer dígito afuera, luego 6 y 6
        const grupo = (desde, txt) => {
          const x = (izq + desde + 2) * u, w = 38 * u;   // 42 módulos del grupo, con aire a los lados
          return `<text x="${x.toFixed(3)}" y="${y}" font-size="${fs}" textLength="${w.toFixed(3)}" lengthAdjust="spacingAndGlyphs">${txt}</text>`;
        };
        numeros = `<text x="${((izq - 1.5) * u).toFixed(3)}" y="${y}" font-size="${fs}" text-anchor="end">${codigo[0]}</text>
          ${grupo(3, codigo.slice(1, 7))}${grupo(50, codigo.slice(7))}`;
      } else {
        const esc = codigo.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
        numeros = `<text x="${(ancho / 2).toFixed(2)}" y="${y}" font-size="${fs}" text-anchor="middle">${esc}</text>`;
      }
    }

    const interior = `<g fill="#000" shape-rendering="crispEdges">${barras}</g>
        <g fill="#000" font-family="Arial, Helvetica, sans-serif" font-weight="700">${numeros}</g>`;
    return {
      ancho,
      interior,
      cabe: ancho <= anchoMm + 0.01,
      svg: `<svg xmlns="http://www.w3.org/2000/svg" width="${ancho.toFixed(3)}mm" height="${altoMm}mm"
        viewBox="0 0 ${ancho.toFixed(3)} ${altoMm}" shape-rendering="crispEdges">
        <g fill="#000">${barras}</g>
        <g fill="#000" font-family="Arial, Helvetica, sans-serif" font-weight="700">${numeros}</g></svg>`
    };
  }

  const escXml = (t) => String(t ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
  const limitar = (v, min, max) => Math.max(min, Math.min(max, v));
  const pesos = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });

  // Parte el nombre en máximo `max` líneas que quepan en el ancho; si sobra, termina en "…"
  function partirNombre(nombre, anchoMm, fs, max) {
    const porLinea = Math.max(6, Math.floor(anchoMm / (fs * 0.64)));
    const palabras = String(nombre).trim().split(/\s+/);
    const lineas = [];
    let actual = '';
    for (let i = 0; i < palabras.length; i++) {
      let p = palabras[i];
      if (p.length > porLinea) p = p.slice(0, porLinea);
      const prueba = actual ? `${actual} ${p}` : p;
      if (prueba.length <= porLinea) { actual = prueba; continue; }
      lineas.push(actual);
      actual = p;
      if (lineas.length === max) { actual = ''; break; }
    }
    if (actual && lineas.length < max) lineas.push(actual);
    const usadas = lineas.join(' ').split(/\s+/).filter(Boolean).length;
    if (usadas < palabras.length && lineas.length) {
      const u = lineas.length - 1;
      lineas[u] = (lineas[u].length >= porLinea ? lineas[u].slice(0, porLinea - 1) : lineas[u]) + '…';
    }
    return lineas;
  }

  // Etiqueta completa: código solo, o con nombre del producto y/o precio.
  // contenido: { nombre?: string, precio?: number }
  function svgEtiqueta(codigo, { anchoMm, altoMm, nombre = '', precio = null }) {
    const conNombre = !!String(nombre || '').trim();
    const conPrecio = precio != null && precio !== '' && !Number.isNaN(Number(precio));
    if (!conNombre && !conPrecio) return svgCodigo(codigo, { anchoMm, altoMm });

    const fsN = limitar(altoMm * 0.12, 2.2, 3.4);
    const lineas = conNombre ? partirNombre(nombre, anchoMm, fsN, 2) : [];
    const altoNombre = lineas.length ? lineas.length * fsN * 1.18 + 0.5 : 0;
    const fsP = limitar(altoMm * 0.17, 3, 5.5);
    const altoPrecio = conPrecio ? fsP * 1.05 + 0.5 : 0;
    const altoCod = altoMm - altoNombre - altoPrecio;
    const c = svgCodigo(codigo, { anchoMm, altoMm: Math.max(altoCod, 4) });
    const W = anchoMm;
    const x0 = Math.max(0, (W - c.ancho) / 2);

    // Si una línea queda más ancha que la etiqueta (letras anchas), se comprime para que quepa
    const ajuste = (txt, fs) => (txt.length * fs * 0.66 > W * 0.98
      ? ` textLength="${(W * 0.98).toFixed(2)}" lengthAdjust="spacingAndGlyphs"` : '');
    const textoNombre = lineas.map((l, i) =>
      `<text x="${(W / 2).toFixed(2)}" y="${((i + 1) * fsN * 1.18 - fsN * 0.22).toFixed(2)}" font-size="${fsN.toFixed(2)}" text-anchor="middle"${ajuste(l, fsN)}>${escXml(l)}</text>`).join('');
    const textoPrecio = conPrecio
      ? `<text x="${(W / 2).toFixed(2)}" y="${(altoMm - 0.3).toFixed(2)}" font-size="${fsP.toFixed(2)}" font-weight="900" text-anchor="middle">${escXml(pesos.format(Number(precio)))}</text>`
      : '';

    return {
      ancho: W,
      cabe: c.cabe && altoCod >= 8,
      motivo: altoCod < 8 ? 'alto' : (!c.cabe ? 'ancho' : ''),
      svg: `<svg xmlns="http://www.w3.org/2000/svg" width="${W.toFixed(3)}mm" height="${altoMm}mm" viewBox="0 0 ${W.toFixed(3)} ${altoMm}">
        <g fill="#000" font-family="Arial, Helvetica, sans-serif" font-weight="700">${textoNombre}${textoPrecio}</g>
        <g transform="translate(${x0.toFixed(3)} ${altoNombre.toFixed(3)})">${c.interior}</g></svg>`
    };
  }

  // Ancho que de verdad imprime el cabezal. En rollos de 58 y 80 mm (impresoras
  // de tickets como la DIG-M220) el cabezal cubre 48 y 72 mm, centrados.
  const anchoUtil = (ancho) => (ancho === 58 ? 48 : ancho === 80 ? 72 : ancho - 3);

  function htmlEtiquetas(codigo, cantidad, { ancho = 40, alto = 30 } = {}, contenido = {}) {
    const margen = 1.5;
    const { svg } = svgEtiqueta(codigo, { anchoMm: anchoUtil(ancho), altoMm: alto - 2 * margen, ...contenido });
    const una = `<div class="et">${svg}</div>`;
    return `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Etiquetas ${codigo}</title>
      <style>
        @page { size: ${ancho}mm ${alto}mm; margin: 0; }
        * { margin: 0; padding: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        html, body { background: #fff; }
        .et { width: ${ancho}mm; height: ${alto}mm; padding: ${margen}mm; box-sizing: border-box;
              display: flex; align-items: center; justify-content: center; overflow: hidden;
              break-after: page; page-break-after: always; }
        .et:last-child { break-after: auto; page-break-after: auto; }
        svg { display: block; }
      </style></head><body>${una.repeat(cantidad)}</body></html>`;
  }

  function imprimirEtiquetas(codigo, cantidad, medida, contenido = {}) {
    const marco = document.createElement('iframe');
    marco.setAttribute('aria-hidden', 'true');
    marco.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;';
    document.body.appendChild(marco);
    const doc = marco.contentDocument;
    doc.open();
    doc.write(htmlEtiquetas(codigo, cantidad, medida, contenido));
    doc.close();
    const quitar = () => setTimeout(() => marco.remove(), 500);
    marco.contentWindow.addEventListener('afterprint', quitar);
    setTimeout(() => {
      marco.contentWindow.focus();
      marco.contentWindow.print();
      setTimeout(() => marco.isConnected && marco.remove(), 60000);
    }, 250);
  }

  Object.assign(window, { anchoUtil, codigoInterno, esEan13, esInterno, svgCodigo, svgEtiqueta, htmlEtiquetas, imprimirEtiquetas });
})();
