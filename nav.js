// Barra de navegación común a todas las pantallas.
// Uso: <nav class="nav" id="nav" aria-label="Secciones"></nav><script src="nav.js?v=2"></script>
// justo en la cabecera (se ejecuta en el momento y llena la barra).
// En el celular (≤ 700 px) la barra pasa abajo: Caja, Pedidos, Inventario, Cartera y "Más".
// Después de iniciar sesión, cada pantalla llama navPendientes(db) para el contador de pedidos.
(() => {
  const ICONOS = {
    caja: '<rect x="3" y="9" width="18" height="11" rx="2"/><path d="M7 9V5h10v4M7 14h4"/>',
    cotizaciones: '<path d="M6 3h9l4 4v14H6z"/><path d="M14 3v5h5M9 13h7M9 17h5"/>',
    pedidos: '<path d="M3 7l9-4 9 4v10l-9 4-9-4z"/><path d="M3 7l9 4 9-4M12 11v10"/>',
    inventario: '<rect x="5" y="7" width="14" height="14" rx="2"/><path d="M5 11h14M9 7V3h6v4"/>',
    cartera: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M3 10h18M16 15h2"/>',
    gastos: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>',
    tablero: '<path d="M4 20V10M10 20V4M16 20v-7M2 20h20"/>',
    mas: '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>'
  };
  // [archivo, nombre, ícono, ¿va en la barra del celular?]
  const SECCIONES = [
    ['index.html', 'Caja', 'caja', true],
    ['cotizaciones.html', 'Cotizaciones', 'cotizaciones', false],
    ['pedidos.html', 'Pedidos', 'pedidos', true],
    ['inventario.html', 'Inventario', 'inventario', true],
    ['cartera.html', 'Cartera', 'cartera', true],
    ['gastos.html', 'Gastos', 'gastos', false],
    ['tablero.html', 'Tablero', 'tablero', false]
  ];
  const icono = (k) => `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONOS[k]}</svg>`;
  const pagina = decodeURIComponent(location.pathname.split('/').pop()) || 'index.html';
  const nav = document.getElementById('nav');
  if (!nav) return;

  const enlace = ([href, nombre, ic, principal]) => `
    <a href="${href}" class="${principal ? '' : 'nav-secundaria'}"${href === pagina ? ' aria-current="page"' : ''}>
      ${icono(ic)}<span>${nombre}</span>${ic === 'pedidos' ? '<b class="nav-cuenta" data-pedidos hidden></b>' : ''}
    </a>`;
  const secundariaActual = SECCIONES.some(([h, , , p]) => h === pagina && !p);
  nav.innerHTML = SECCIONES.map(enlace).join('') + `
    <button type="button" class="nav-mas"${secundariaActual ? ' aria-current="page"' : ''} aria-expanded="false" aria-controls="navMenu">${icono('mas')}<span>Más</span></button>
    <div class="nav-menu" id="navMenu" hidden>
      ${SECCIONES.filter((s) => !s[3]).map(([href, nombre, ic]) =>
        `<a href="${href}"${href === pagina ? ' aria-current="page"' : ''}>${icono(ic)}<span>${nombre}</span></a>`).join('')}
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
    #nav { display: flex; flex-wrap: wrap; gap: 2px; margin: 0 auto 0 1rem; } /* pegada a la marca: no se mueve según lo que haya a la derecha */
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
    #nav .nav-mas, #nav .nav-menu { display: none; }
    @media (max-width: 1180px) and (min-width: 701px) {
      #nav { order: 3; width: 100%; justify-content: center; margin: 0; }
    }
    @media (max-width: 700px) {
      #nav {
        position: fixed; left: 0; right: 0; bottom: 0; z-index: 40; margin: 0;
        display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 0;
        padding: .25rem .25rem calc(.4rem + env(safe-area-inset-bottom));
        background: var(--panel); border-top: 1px solid var(--linea);
      }
      #nav a, #nav .nav-mas {
        flex-direction: column; justify-content: center; gap: .1rem; min-height: 3.2rem;
        padding: .3rem 0; font-size: .75rem; background: none; text-align: center;
      }
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
      body { padding-bottom: calc(4.2rem + env(safe-area-inset-bottom)); }
      #aviso { bottom: calc(4.6rem + env(safe-area-inset-bottom)) !important; }
    }
    @media print { #nav { display: none !important; } }
  `;
  document.head.appendChild(estilo);

  // Pedidos por atender (pendientes y confirmados). Sin conexión, simplemente no se muestra.
  window.navPendientes = async (db) => {
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
})();
