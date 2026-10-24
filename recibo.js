// Recibo imprimible (impresora térmica de 58/80 mm o impresora normal).
// Uso: imprimirRecibo({ id, fecha, cliente, vendedor, metodo, estado,
//        items: [{ etiqueta, cantidad, precio }], subtotal, descuento, recargo, motivo, total,
//        recibido, copia })
(function () {
  const cop = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });
  const cant = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 2 });
  const fHora = new Intl.DateTimeFormat('es-CO', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Bogota' });
  const METODOS = { efectivo: 'Efectivo', transferencia: 'Transferencia', tarjeta: 'Tarjeta', credito: 'Crédito' };
  const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  window.imprimirRecibo = function (v) {
    const cfg = window.APP_CONFIG || {};
    const n = cfg.NEGOCIO || {};
    const ancho = cfg.ANCHO_RECIBO || '58mm';
    // Ancho que de verdad imprime el cabezal: 58 mm -> 48 mm útiles, 80 mm -> 72 mm
    const util = cfg.ANCHO_IMPRESION || (ancho === '58mm' ? '48mm' : '72mm');

    const lineas = v.items.map((i) => `
      <tr><td colspan="2" class="prod">${esc(i.etiqueta)}</td></tr>
      <tr><td>${cant.format(i.cantidad)} x ${cop.format(i.precio)}</td>
          <td class="der">${cop.format(i.cantidad * i.precio)}</td></tr>`).join('');

    const filas = [];
    const recargo = Number(v.recargo) || 0;
    if (v.descuento > 0 || recargo > 0) {
      filas.push(`<tr><td>Subtotal</td><td class="der">${cop.format(v.subtotal)}</td></tr>`);
      if (v.descuento > 0) filas.push(`<tr><td>Descuento</td><td class="der">-${cop.format(v.descuento)}</td></tr>`);
      if (recargo > 0) filas.push(`<tr><td>Recargo</td><td class="der">+${cop.format(recargo)}</td></tr>`);
      if (v.motivo) filas.push(`<tr><td colspan="2" class="motivo">Motivo: ${esc(v.motivo)}</td></tr>`);
    }
    filas.push(`<tr class="total"><td>TOTAL</td><td class="der">${cop.format(v.total)}</td></tr>`);
    filas.push(`<tr><td>Pago</td><td class="der">${METODOS[v.metodo] ?? v.metodo}</td></tr>`);
    if (v.metodo === 'efectivo' && v.recibido != null) {
      filas.push(`<tr><td>Recibido</td><td class="der">${cop.format(v.recibido)}</td></tr>`);
      filas.push(`<tr><td>Cambio</td><td class="der">${cop.format(v.recibido - v.total)}</td></tr>`);
    }

    const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
      <title>Recibo ${v.id}</title>
      <style id="estilo">
        @page { size: ${ancho} 100mm; margin: 0; }
        * { box-sizing: border-box; color: #000 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        /* Térmica: negro puro, letra gruesa y nada de grises (salen pálidos) */
        body { margin: 0 auto; padding: 1mm 0 3mm; width: ${util}; background: #fff;
               font: 700 ${ancho === '58mm' ? 12 : 13.5}px/1.35 Arial, Helvetica, sans-serif;
               letter-spacing: .01em; -webkit-font-smoothing: none; }
        h1 { font-size: ${ancho === '58mm' ? 16 : 19}px; font-weight: 900; text-align: center; margin: 0 0 3px; }
        .c { text-align: center; }
        hr { border: 0; border-top: 2px solid #000; margin: 6px 0; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 1px 0; vertical-align: top; font-weight: 700; }
        .der { text-align: right; white-space: nowrap; padding-left: 6px; }
        .prod { padding-top: 5px; overflow-wrap: anywhere; }
        .total td { font-size: ${ancho === '58mm' ? 16 : 19}px; font-weight: 900; padding-top: 5px; }
        .motivo { padding-bottom: 3px; overflow-wrap: anywhere; }
        .nota { font-size: ${ancho === '58mm' ? 10.5 : 11.5}px; margin-top: 4px; }
      </style></head><body>
      <h1>${esc(cfg.NOMBRE_TIENDA)}</h1>
      ${n.NIT ? `<div class="c">NIT ${esc(n.NIT)}</div>` : ''}
      ${n.DIRECCION ? `<div class="c">${esc(n.DIRECCION)}</div>` : ''}
      ${n.TELEFONO ? `<div class="c">Tel. ${esc(n.TELEFONO)}</div>` : ''}
      <hr>
      <div>Recibo N.° ${v.id}${v.copia ? ' (copia)' : ''}</div>
      ${v.provisional ? '<div><b>PROVISIONAL:</b> registrado sin conexión. Se asienta al volver internet.</div>' : ''}
      <div>${fHora.format(new Date(v.fecha))}</div>
      <div>Cliente: ${esc(v.cliente || 'Consumidor final')}</div>
      ${v.vendedor ? `<div>Atendió: ${esc(v.vendedor)}</div>` : ''}
      <hr>
      <table>${lineas}</table>
      <hr>
      <table>${filas.join('')}</table>
      ${v.metodo === 'credito' && v.estado !== 'anulada' ? '<div class="c" style="margin-top:6px">Venta a crédito: saldo pendiente de pago</div>' : ''}
      ${v.estado === 'anulada' ? '<div class="c" style="margin-top:6px"><b>VENTA ANULADA</b></div>' : ''}
      <hr>
      <div class="c">${esc(n.PIE || 'Gracias por su compra')}</div>
      <div class="c nota">Comprobante interno. No es factura electrónica.</div>
      </body></html>`;

    const marco = document.createElement('iframe');
    marco.setAttribute('aria-hidden', 'true');
    // Fuera de la vista pero con ancho real: así se puede medir el alto del recibo
    marco.style.cssText = 'position:fixed;left:-10000px;top:0;width:420px;height:200px;border:0;visibility:hidden;';
    document.body.appendChild(marco);
    const doc = marco.contentDocument;
    doc.open();
    doc.write(html);
    doc.close();

    const quitar = () => setTimeout(() => marco.remove(), 500);
    marco.contentWindow.addEventListener('afterprint', quitar);
    setTimeout(() => {
      // Papel continuo: la hoja mide exactamente lo que mide el contenido.
      // Sin esto, el navegador usa la hoja del driver (a veces A4 o 3 metros)
      // y la impresora bota papel en blanco o deja el texto al final.
      const estilo = doc.getElementById('estilo');
      if (estilo) {
        const mm = Math.ceil(doc.documentElement.scrollHeight * 25.4 / 96) + 3;
        estilo.textContent = estilo.textContent.replace(/size:\s*(\S+)\s+100mm/, `size: $1 ${mm}mm`);
      }
      marco.contentWindow.focus();
      marco.contentWindow.print();
      setTimeout(() => marco.isConnected && marco.remove(), 60000);   // respaldo si no llega afterprint
    }, 250);
  };
})();
