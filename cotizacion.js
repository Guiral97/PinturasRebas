// Cotización imprimible: hoja carta (o guardar como PDF desde el diálogo
// de impresión) o ticket térmico de 58/80 mm.
// Uso: imprimirCotizacion({ id, fecha, valida_hasta, cliente, documento, telefono,
//        vendedor, notas, items: [{ etiqueta, codigo, cantidad, precio }],
//        subtotal, descuento, total }, 'carta' | 'ticket')
(function () {
  const cop = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });
  const cant = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 2 });
  const fLarga = new Intl.DateTimeFormat('es-CO', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Bogota' });
  const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // 'AAAA-MM-DD' se lee como fecha local (al mediodía, para no cruzar de día)
  const fechaDia = (d) => new Date(`${d}T12:00:00`);

  const CONDICIONES_BASE =
    'Precios en pesos colombianos. Sujeto a disponibilidad de inventario al momento del pedido.';

  function cartaHtml(c, cfg) {
    const n = cfg.NEGOCIO || {};
    const datosNegocio = [n.NIT ? `NIT ${esc(n.NIT)}` : '', esc(n.DIRECCION), n.TELEFONO ? `Tel. ${esc(n.TELEFONO)}` : '']
      .filter(Boolean).join(' · ');
    const filas = c.items.map((i, k) => `
      <tr>
        <td class="n">${k + 1}</td>
        <td>${esc(i.etiqueta)}${i.codigo ? `<div class="cod">${esc(i.codigo)}</div>` : ''}</td>
        <td class="der">${cant.format(i.cantidad)}</td>
        <td class="der">${cop.format(i.precio)}</td>
        <td class="der">${cop.format(i.cantidad * i.precio)}</td>
      </tr>`).join('');
    const condiciones = cfg.CONDICIONES_COTIZACION || CONDICIONES_BASE;

    return `<!doctype html><html lang="es"><head><meta charset="utf-8">
      <title>Cotización ${c.id}</title>
      <style>
        @page { size: letter; margin: 16mm 15mm; }
        * { box-sizing: border-box; }
        body { margin: 0; color: #111; -webkit-print-color-adjust: exact; print-color-adjust: exact; font: 10.5pt/1.4 "Barlow", "Segoe UI", Arial, sans-serif; }
        .cab { display: flex; justify-content: space-between; align-items: flex-end; gap: 12mm;
               border-bottom: 2.5pt solid #0E5266; padding-bottom: 4mm; }
        .tienda { font: 700 20pt/1.1 "Barlow Condensed", "Arial Narrow", Arial, sans-serif; margin: 0; }
        .neg { color: #2E3438; margin-top: 1mm; }
        .doc { text-align: right; }
        .doc .t { font: 700 15pt/1 "Barlow Condensed", "Arial Narrow", Arial, sans-serif; color: #0E5266; letter-spacing: .04em; }
        .doc .num { font-size: 13pt; font-weight: 600; margin-top: 1mm; }
        .datos { display: grid; grid-template-columns: 1fr 1fr; gap: 6mm; margin: 6mm 0 5mm; }
        .datos h3 { font-size: 8.5pt; text-transform: uppercase; letter-spacing: .06em; color: #2E3438; margin: 0 0 1mm; }
        .datos p { margin: 0; }
        table { width: 100%; border-collapse: collapse; }
        th { font-size: 8.5pt; text-transform: uppercase; letter-spacing: .04em; color: #2E3438; text-align: left;
             border-bottom: 1pt solid #1A2127; padding: 1.5mm 2mm; }
        td { padding: 2mm; border-bottom: .75pt solid #8E938E; vertical-align: top; }
        .n { width: 8mm; color: #2E3438; }
        .der { text-align: right; white-space: nowrap; }
        .cod { color: #2E3438; font-size: 8.5pt; }
        .totales { margin: 4mm 0 0 auto; width: 70mm; }
        .totales td { border: 0; padding: 1mm 2mm; }
        .totales .total td { border-top: 1.5pt solid #1A2127; font-size: 13pt; font-weight: 700; padding-top: 2mm; }
        .vig { margin-top: 7mm; padding: 3mm 4mm; background: #F3EBD2; border-left: 3pt solid #C9AE66; }
        .notas, .cond { margin-top: 4mm; }
        .cond { color: #2E3438; font-size: 9pt; }
        .pie { margin-top: 10mm; padding-top: 3mm; border-top: .75pt solid #8E938E; color: #2E3438; font-size: 8.5pt;
               display: flex; justify-content: space-between; gap: 6mm; }
        tr, .totales, .vig { break-inside: avoid; }
      </style></head><body>
      <div class="cab">
        <div>
          <p class="tienda">${esc(cfg.NOMBRE_TIENDA)}</p>
          ${datosNegocio ? `<div class="neg">${datosNegocio}</div>` : ''}
        </div>
        <div class="doc">
          <div class="t">COTIZACIÓN</div>
          <div class="num">N.° ${c.id}</div>
        </div>
      </div>

      <div class="datos">
        <div>
          <h3>Cliente</h3>
          <p><strong>${esc(c.cliente)}</strong></p>
          ${c.documento ? `<p>Documento: ${esc(c.documento)}</p>` : ''}
          ${c.telefono ? `<p>Teléfono: ${esc(c.telefono)}</p>` : ''}
        </div>
        <div>
          <h3>Fecha</h3>
          <p>${fLarga.format(new Date(c.fecha))}</p>
          <h3 style="margin-top:2mm">Válida hasta</h3>
          <p><strong>${fLarga.format(fechaDia(c.valida_hasta))}</strong></p>
        </div>
      </div>

      <table>
        <thead><tr><th class="n">#</th><th>Producto</th><th class="der">Cant.</th><th class="der">Precio</th><th class="der">Valor</th></tr></thead>
        <tbody>${filas}</tbody>
      </table>

      <table class="totales">
        ${c.descuento > 0 ? `
          <tr><td>Subtotal</td><td class="der">${cop.format(c.subtotal)}</td></tr>
          <tr><td>Descuento</td><td class="der">-${cop.format(c.descuento)}</td></tr>` : ''}
        <tr class="total"><td>Total</td><td class="der">${cop.format(c.total)}</td></tr>
      </table>

      <div class="vig">Precios garantizados hasta el <strong>${fLarga.format(fechaDia(c.valida_hasta))}</strong>.</div>
      ${c.notas ? `<p class="notas"><strong>Notas:</strong> ${esc(c.notas)}</p>` : ''}
      <p class="cond">${esc(condiciones)}</p>

      <div class="pie">
        <span>${c.vendedor ? `Elaboró: ${esc(c.vendedor)}` : ''}</span>
        <span>Documento informativo. No es factura.</span>
      </div>
      </body></html>`;
  }

  function ticketHtml(c, cfg) {
    const n = cfg.NEGOCIO || {};
    const ancho = cfg.ANCHO_RECIBO || '80mm';
    const lineas = c.items.map((i) => `
      <tr><td colspan="2" class="prod">${esc(i.etiqueta)}</td></tr>
      <tr><td>${cant.format(i.cantidad)} x ${cop.format(i.precio)}</td>
          <td class="der">${cop.format(i.cantidad * i.precio)}</td></tr>`).join('');
    return `<!doctype html><html lang="es"><head><meta charset="utf-8">
      <title>Cotización ${c.id}</title>
      <style>
        @page { size: ${ancho} auto; margin: 2mm; }
        * { box-sizing: border-box; color: #000 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body { margin: 0; width: calc(${ancho} - 4mm); background: #fff;
               font: 700 ${ancho === '58mm' ? 12 : 13.5}px/1.35 Arial, Helvetica, sans-serif; letter-spacing: .01em; }
        h1 { font-size: ${ancho === '58mm' ? 16 : 19}px; font-weight: 900; text-align: center; margin: 0 0 3px; }
        .c { text-align: center; }
        hr { border: 0; border-top: 2px solid #000; margin: 6px 0; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 1px 0; vertical-align: top; font-weight: 700; }
        .der { text-align: right; white-space: nowrap; padding-left: 6px; }
        .prod { padding-top: 5px; }
        .total td { font-size: ${ancho === '58mm' ? 16 : 19}px; font-weight: 900; padding-top: 5px; }
        .nota { font-size: ${ancho === '58mm' ? 10.5 : 11.5}px; margin-top: 4px; }
      </style></head><body>
      <h1>${esc(cfg.NOMBRE_TIENDA)}</h1>
      ${n.NIT ? `<div class="c">NIT ${esc(n.NIT)}</div>` : ''}
      ${n.TELEFONO ? `<div class="c">Tel. ${esc(n.TELEFONO)}</div>` : ''}
      <hr>
      <div class="c"><b>COTIZACIÓN N.° ${c.id}</b></div>
      <div>${fLarga.format(new Date(c.fecha))}</div>
      <div>Cliente: ${esc(c.cliente)}</div>
      <hr>
      <table>${lineas}</table>
      <hr>
      <table>
        ${c.descuento > 0 ? `<tr><td>Subtotal</td><td class="der">${cop.format(c.subtotal)}</td></tr>
          <tr><td>Descuento</td><td class="der">-${cop.format(c.descuento)}</td></tr>` : ''}
        <tr class="total"><td>TOTAL</td><td class="der">${cop.format(c.total)}</td></tr>
      </table>
      <hr>
      <div class="c">Válida hasta el ${fLarga.format(fechaDia(c.valida_hasta))}</div>
      <div class="c nota">Documento informativo. No es factura.</div>
      </body></html>`;
  }

  window.imprimirCotizacion = function (c, formato = 'carta') {
    const cfg = window.APP_CONFIG || {};
    const html = formato === 'ticket' ? ticketHtml(c, cfg) : cartaHtml(c, cfg);

    const marco = document.createElement('iframe');
    marco.setAttribute('aria-hidden', 'true');
    marco.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;';
    document.body.appendChild(marco);
    const doc = marco.contentDocument;
    doc.open();
    doc.write(html);
    doc.close();

    const quitar = () => setTimeout(() => marco.remove(), 500);
    marco.contentWindow.addEventListener('afterprint', quitar);
    setTimeout(() => {
      marco.contentWindow.focus();
      marco.contentWindow.print();
      setTimeout(() => marco.isConnected && marco.remove(), 60000);   // respaldo si no llega afterprint
    }, 250);
  };

  // Para pruebas y vista previa: devuelve el HTML sin imprimir
  window.htmlCotizacion = (c, formato = 'carta') =>
    formato === 'ticket' ? ticketHtml(c, window.APP_CONFIG || {}) : cartaHtml(c, window.APP_CONFIG || {});
})();
