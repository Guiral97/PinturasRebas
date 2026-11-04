// Barra de navegación común a todas las pantallas.
// Uso: <nav class="nav" id="nav" aria-label="Secciones"></nav><script src="nav.js?v=10"></script>
// justo en la cabecera (se ejecuta en el momento y llena la barra).
// Con sesión, en escritorio (> 1180 px) la cabecera pasa a ser una barra lateral con las secciones por grupos;
// en tableta (701–1180 px) la misma barra muestra solo íconos.
// En el celular (≤ 700 px) la barra pasa abajo: Caja, Pedidos, Inventario, Cartera y "Más".
// Después de iniciar sesión, cada pantalla llama navPendientes(db) para el contador de pedidos
// y para mostrar "Usuarios" si quien entró es socio.
(() => {
  const ICONOS = {
    caja: '<rect x="3" y="9" width="18" height="11" rx="2"/><path d="M7 9V5h10v4M7 14h4"/>',
    cotizaciones: '<path d="M6 3h9l4 4v14H6z"/><path d="M14 3v5h5M9 13h7M9 17h5"/>',
    pedidos: '<path d="M3 7l9-4 9 4v10l-9 4-9-4z"/><path d="M3 7l9 4 9-4M12 11v10"/>',
    inventario: '<rect x="5" y="7" width="14" height="14" rx="2"/><path d="M5 11h14M9 7V3h6v4"/>',
    catalogo: '<path d="M4 9.5 5.5 4h13L20 9.5"/><path d="M4 9.5c0 1.4 1.2 2.5 2.7 2.5s2.6-1.1 2.6-2.5c0 1.4 1.2 2.5 2.7 2.5s2.7-1.1 2.7-2.5c0 1.4 1.2 2.5 2.6 2.5S20 10.9 20 9.5"/><path d="M5.5 12v8h13v-8M10 20v-4.5h4V20"/>',
    cartera: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M3 10h18M16 15h2"/>',
    cierre: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12h.01M18 12h.01"/>',
    conversiones: '<path d="M12 3v17M8 20h8M5 6h14"/><path d="M5 6l-3 7a3 3 0 0 0 6 0zM19 6l-3 7a3 3 0 0 0 6 0z"/>',
    gastos: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>',
    tablero: '<path d="M4 20V10M10 20V4M16 20v-7M2 20h20"/>',
    usuarios: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.6-3.6 3.2-5.5 6.5-5.5s5.9 1.9 6.5 5.5M16 4.8a3.5 3.5 0 0 1 0 6.4M18.5 14.8c1.6.8 2.7 2.5 3 5.2"/>',
    mas: '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>'
  };
  // [archivo, nombre, ícono, ¿va en la barra del celular?, ¿solo socios?]
  // Por grupos: en escritorio la barra lateral muestra el nombre de cada grupo. [nombre, secciones, ¿solo socios?]
  const GRUPOS = [
    ['Vender', [
      ['index.html', 'Caja', 'caja', true],
      ['cotizaciones.html', 'Cotizaciones', 'cotizaciones', false],
      ['pedidos.html', 'Pedidos', 'pedidos', true]
    ]],
    ['Mercancía', [
      ['inventario.html', 'Inventario', 'inventario', true],
      ['catalogo-web.html', 'Catálogo', 'catalogo', false],
      ['conversiones.html', 'Conversiones', 'conversiones', false]
    ]],
    ['Dinero', [
      ['cartera.html', 'Cartera', 'cartera', true],
      ['cierre.html', 'Cierre de caja', 'cierre', false],
      ['gastos.html', 'Gastos', 'gastos', false],
      ['tablero.html', 'Tablero', 'tablero', false]
    ]],
    ['Administrar', [
      ['usuarios.html', 'Usuarios', 'usuarios', false, true]
    ], true]
  ];
  const SECCIONES = GRUPOS.flatMap(([, secciones]) => secciones);
  const icono = (k) => `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONOS[k]}</svg>`;
  const pagina = decodeURIComponent(location.pathname.split('/').pop()) || 'index.html';
  const nav = document.getElementById('nav');
  if (!nav) return;

  const soloSocios = (socio) => (socio ? ' data-socio hidden' : '');
  const enlace = ([href, nombre, ic, principal, socio]) => `
    <a href="${href}" title="${nombre}" class="${principal ? '' : 'nav-secundaria'}"${href === pagina ? ' aria-current="page"' : ''}${soloSocios(socio)}>
      ${icono(ic)}<span data-t="${nombre}">${nombre}</span>${ic === 'pedidos' ? '<b class="nav-cuenta" data-pedidos hidden></b>' : ''}
    </a>`;
  const secundariaActual = SECCIONES.some(([h, , , p]) => h === pagina && !p);
  nav.innerHTML = GRUPOS.map(([grupo, secciones, socio]) =>
    `<span class="nav-grupo"${soloSocios(socio)}>${grupo}</span>` + secciones.map(enlace).join('')).join('') + `
    <button type="button" class="nav-mas"${secundariaActual ? ' aria-current="page"' : ''} aria-expanded="false" aria-controls="navMenu">${icono('mas')}<span data-t="Más">Más</span></button>
    <div class="nav-menu" id="navMenu" hidden>
      ${SECCIONES.filter((s) => !s[3]).map(([href, nombre, ic, , socio]) =>
        `<a href="${href}"${href === pagina ? ' aria-current="page"' : ''}${soloSocios(socio)}>${icono(ic)}<span data-t="${nombre}">${nombre}</span></a>`).join('')}
    </div>`;

  const mas = nav.querySelector('.nav-mas'), menu = nav.querySelector('.nav-menu');
  const cerrar = () => { menu.hidden = true; mas.setAttribute('aria-expanded', 'false'); };
  mas.addEventListener('click', () => {
    menu.hidden = !menu.hidden;
    mas.setAttribute('aria-expanded', String(!menu.hidden));
  });
  document.addEventListener('click', (e) => { if (!nav.contains(e.target)) cerrar(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !menu.hidden) { cerrar(); mas.focus(); } });

  // Con id: gana sobre las reglas .nav que traiga cada pantalla
  const estilo = document.createElement('style');
  estilo.textContent = `
    /* flex: 1 ocupa el espacio libre: la barra arranca junto a la marca y no se mueve según lo que haya a la derecha */
    #nav { display: flex; flex-wrap: wrap; gap: 2px; flex: 1; margin: 0; }
    /* Reserva el ancho en negrita para que el botón activo no empuje a los demás */
    #nav a > span, #nav .nav-mas > span { display: inline-flex; flex-direction: column; align-items: center; }
    #nav a > span::after, #nav .nav-mas > span::after { content: attr(data-t); font-weight: 600; height: 0; overflow: hidden; visibility: hidden; }
    #nav a, #nav .nav-mas {
      position: relative; display: flex; align-items: center; gap: .45rem;
      padding: .45rem .7rem; border-radius: 8px; border: 0; background: none; box-shadow: none;
      color: var(--suave); font: inherit; font-weight: 500; text-decoration: none; white-space: nowrap; cursor: pointer;
    }
    #nav a:hover, #nav .nav-mas:hover { color: var(--tinta); background: color-mix(in srgb, var(--acento) 8%, transparent); }
    #nav a[aria-current="page"], #nav .nav-mas[aria-current="page"] {
      color: var(--tinta); font-weight: 600; background: color-mix(in srgb, var(--acento) 16%, transparent);
    }
    #nav a[aria-current="page"] svg { color: var(--acento); }
    #nav .nav-cuenta {
      font-size: .72rem; font-weight: 700; line-height: 1.35; padding: 0 .4rem; border-radius: 999px;
      color: #1A2127; background: #E3B94F;
    }
    #nav .nav-mas, #nav .nav-menu, #nav .nav-grupo { display: none; }
    #nav [hidden] { display: none !important; }

    /* ===== Escritorio y tableta (≥ 701 px): con sesión, la cabecera pasa a ser una barra lateral fija ===== */
    @media (min-width: 701px) {
      :root { --nav-ancho: 14.5rem; }
      body:has(main#app:not([hidden]), main#pos:not([hidden])) { padding-left: var(--nav-ancho); }
      body:has(main#app:not([hidden]), main#pos:not([hidden])) header.barra:has(#nav) {
        position: fixed; top: 0; left: 0; bottom: 0; z-index: 30; width: var(--nav-ancho); box-sizing: border-box;
        display: flex; flex-direction: column; flex-wrap: nowrap; align-items: stretch; gap: .3rem;
        padding: .9rem .7rem; border-bottom: 0; border-right: 1px solid var(--linea);
        overflow-y: auto; overscroll-behavior: contain;
      }
      header.barra:has(#nav) .marca { margin: 0 0 .35rem; padding: 0 .35rem; }
      header.barra:has(#nav) .logo { height: 2.7rem; margin: 0; }
      header.barra:has(#nav) .tienda { font-size: 1.3rem; line-height: 1.05; }
      #nav { flex: 1 0 auto; flex-direction: column; flex-wrap: nowrap; gap: 1px; }
      #nav a > span { align-items: flex-start; }
      #nav .nav-grupo {
        display: block; padding: .85rem .75rem .3rem; font-size: .7rem; font-weight: 700;
        letter-spacing: .08em; text-transform: uppercase; color: var(--suave);
      }
      #nav .nav-grupo:first-child { padding-top: .3rem; }
      #nav a { min-height: 2.6rem; padding: .35rem .75rem; }
      #nav .nav-cuenta { margin-left: auto; }
      header.barra:has(#nav) #usuario {
        display: block; margin-top: .4rem; padding: .7rem .75rem 0; border-top: 1px solid var(--linea);
        font-size: .9rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
      header.barra:has(#nav) #salir { margin: 0 .1rem; }
      header.barra:has(#nav) .red { align-self: stretch; justify-content: center; margin: .4rem .1rem 0; }
    }
    /* Tableta: solo íconos; el nombre queda para lectores de pantalla y en el globo al pasar el ratón */
    @media (min-width: 701px) and (max-width: 1180px) {
      :root { --nav-ancho: 4.75rem; }
      body:has(main#app:not([hidden]), main#pos:not([hidden])) header.barra:has(#nav) { padding: .75rem .45rem; align-items: center; }
      header.barra:has(#nav) .marca { padding: 0; margin-bottom: .2rem; }
      header.barra:has(#nav) .tienda, header.barra:has(#nav) #usuario { display: none; }
      #nav { align-items: center; }
      #nav a { width: 3.5rem; justify-content: center; padding: .55rem 0; min-height: 2.9rem; }
      #nav a > span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
      #nav .nav-grupo { width: 2.5rem; height: 1px; padding: 0; margin: .45rem 0; font-size: 0; background: var(--linea); }
      #nav .nav-grupo:first-child { display: none; }
      #nav .nav-cuenta { position: absolute; top: .1rem; right: .15rem; margin: 0; }
      header.barra:has(#nav) #salir {
        width: 3.75rem; min-height: 2.75rem; padding: .25rem; font-size: .72rem; line-height: 1.1;
        white-space: normal; text-align: center; margin-top: .5rem;
      }
      header.barra:has(#nav) .red { padding: .2rem .35rem; font-size: .7rem; white-space: normal; text-align: center; gap: .25rem; }
    }
    @media (max-width: 700px) {
      #nav {
        position: fixed; left: 0; right: 0; bottom: 0; z-index: 40; margin: 0;
        display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 0;
        padding: .15rem .25rem calc(.2rem + env(safe-area-inset-bottom));
        background: var(--panel); border-top: 1px solid var(--linea);
      }
      #nav a, #nav .nav-mas {
        flex-direction: column; justify-content: center; gap: .05rem; min-height: 2.75rem;
        padding: .2rem 0; font-size: .7rem; background: none; text-align: center;
      }
      #nav svg { width: 19px; height: 19px; }
      #nav a[aria-current="page"], #nav .nav-mas[aria-current="page"] { background: none; color: var(--acento); font-weight: 700; }
      #nav .nav-secundaria { display: none; }
      #nav .nav-mas { display: flex; }
      #nav .nav-cuenta { position: absolute; top: .15rem; left: 50%; margin-left: .45rem; }
      #nav .nav-menu:not([hidden]) {
        display: grid; position: absolute; right: .5rem; bottom: calc(100% + .4rem); min-width: 12rem;
        background: var(--panel); border: 1px solid var(--linea); border-radius: 10px; padding: .3rem;
        box-shadow: 0 8px 24px rgba(0, 0, 0, .25);
      }
      #nav .nav-menu a { flex-direction: row; justify-content: flex-start; gap: .6rem; font-size: 1rem; padding: .7rem .8rem; min-height: 2.75rem; }
      body { padding-bottom: calc(3.6rem + env(safe-area-inset-bottom)); }
      #aviso { bottom: calc(4rem + env(safe-area-inset-bottom)) !important; }
      /* Con el teclado abierto la barra no tapa el campo que se está llenando */
      body:has(input:not([type="checkbox"], [type="radio"], [type="button"]):focus, textarea:focus) #nav { display: none; }
    }

    /* ===== Celular: tamaños compactos comunes a todas las pantallas (cada pantalla ajusta lo suyo) ===== */
    @media (max-width: 700px) {
      body { font-size: 15px; }
      .barra { padding: .35rem .75rem; gap: .4rem .6rem; min-height: 3rem; }
      .barra .logo { height: 1.85rem; margin: 0; }
      .barra .tienda { font-size: 1.1rem; }
      #salir { min-height: 2.25rem; padding: .2rem .6rem; font-size: .85rem; }
      main#app, main#pos { padding: .6rem .75rem; }
      main#app h1, .cab-pagina h1, .titulo-pantalla { font-size: 1.45rem; }
      input:not([type="checkbox"], [type="radio"]), select, textarea { font-size: 15px; padding: .35rem .6rem; }
      input:not([type="checkbox"], [type="radio"]), select, .btn { min-height: 2.5rem; }
      .btn { padding: .35rem .75rem; }
      /* Diálogos como hoja que sube desde abajo, con el pie (Guardar, Registrar…) siempre a la vista */
      dialog[open] {
        width: 100%; max-width: none; max-height: 92dvh; margin: auto 0 0; border-radius: 14px 14px 0 0;
        border-left: 0; border-right: 0; border-bottom: 0; overflow: auto; overscroll-behavior: contain;
      }
      dialog:has(.dlg-cuerpo) { padding: 0; }
      dialog:not(:has(.dlg-cuerpo)) { padding: .9rem .75rem calc(.9rem + env(safe-area-inset-bottom)); }
      dialog .dlg-cuerpo { padding: .85rem .75rem; gap: .8rem; }
      dialog .dlg-pie { padding: .55rem .75rem calc(.55rem + env(safe-area-inset-bottom)); }
    }
    @media print {
      #nav, header.barra:has(#nav) { display: none !important; }
      body { padding-left: 0 !important; }
    }
    /* Solo con sesión: en el ingreso (o mientras se revisa la sesión) no hay secciones a las que ir.
       La pantalla de trabajo es main#app, o main#pos en la caja. */
    body:not(:has(main#app:not([hidden]), main#pos:not([hidden]))) #nav { display: none !important; }
    body:not(:has(main#app:not([hidden]), main#pos:not([hidden]))) { padding-bottom: 0; }
    /* Formulario de ingreso, igual en todas las pantallas */
    #login .olvide { justify-self: center; color: var(--acento); font-weight: 600; text-decoration: none; padding: .5rem; margin-top: -.4rem; }
    #login .olvide:hover { text-decoration: underline; }
  `;
  document.head.appendChild(estilo);

  // Pedidos por atender (pendientes y confirmados). Sin conexión, simplemente no se muestra.
  window.navPendientes = async (db) => {
    navSocio(db);
    const cuenta = nav.querySelector('[data-pedidos]');
    try {
      const { count, error } = await db.from('v_pedidos').select('id', { count: 'exact', head: true })
        .in('estado', ['pendiente', 'confirmado']);
      if (error) return;
      cuenta.textContent = count;
      cuenta.hidden = !count;
      cuenta.setAttribute('aria-label', `${count} por atender`);
    } catch (_) { /* sin conexión */ }
  };

  // "Usuarios" solo para socios (11_usuarios.sql). La página igual lo vuelve a revisar.
  async function navSocio(db) {
    try {
      const { data, error } = await db.rpc('es_socio');
      nav.querySelectorAll('[data-socio]').forEach((a) => (a.hidden = !!error || !data));
    } catch (_) { /* sin conexión */ }
  }
})();
