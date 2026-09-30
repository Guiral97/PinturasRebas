-- =====================================================================
--  Pinturas automotrices: esquema base para Supabase (Postgres 15+)
--  Ejecutar completo en: Supabase > SQL Editor > New query > Run
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Usuarios del sistema (los socios)
-- ---------------------------------------------------------------------
create table public.perfiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nombre     text not null,
  rol        text not null default 'socio' check (rol in ('socio', 'vendedor')),
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- Devuelve true si quien hace la consulta es un usuario activo del negocio.
-- Todas las políticas RLS se apoyan en esta función.
create or replace function public.es_usuario_activo()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles where id = auth.uid() and activo
  );
$$;


-- ---------------------------------------------------------------------
-- 2. Catálogo
-- ---------------------------------------------------------------------
create table public.categorias (
  id      bigint generated always as identity primary key,
  nombre  text not null unique
);

create table public.marcas (
  id      bigint generated always as identity primary key,
  nombre  text not null unique
);

create table public.proveedores (
  id         bigint generated always as identity primary key,
  nombre     text not null,
  nit        text unique,
  telefono   text,
  email      text,
  notas      text,
  creado_en  timestamptz not null default now()
);

-- Un producto es la referencia general (ej: "Base bicapa rojo Mazda 41V")
create table public.productos (
  id            bigint generated always as identity primary key,
  nombre        text not null,
  marca_id      bigint references public.marcas(id),
  categoria_id  bigint references public.categorias(id),
  codigo_color  text,                 -- código de fábrica del color, si aplica
  descripcion   text,
  activo        boolean not null default true,
  creado_en     timestamptz not null default now()
);

-- Una presentación es lo que realmente se vende y se escanea
-- (galón, 1/4, 1/8, unidad, pliego...). Aquí viven precio, costo y código.
create table public.presentaciones (
  id             bigint generated always as identity primary key,
  producto_id    bigint not null references public.productos(id) on delete restrict,
  nombre         text not null,
  sku            text unique,          -- código interno (para lo que no trae código de fábrica)
  codigo_barras  text unique,
  precio_venta   numeric(12,2) not null default 0 check (precio_venta >= 0),
  costo          numeric(12,2) not null default 0 check (costo >= 0),
  stock_minimo   numeric(12,2) not null default 0,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  unique (producto_id, nombre)
);

create table public.clientes (
  id         bigint generated always as identity primary key,
  nombre     text not null,
  documento  text unique,             -- cédula o NIT
  tipo       text not null default 'particular'
             check (tipo in ('particular', 'taller', 'empresa')),
  telefono   text,
  email      text,
  direccion  text,
  creado_en  timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- 3. Pedidos (lo que un cliente encarga antes de pagar/recoger)
-- ---------------------------------------------------------------------
create table public.pedidos (
  id             bigint generated always as identity primary key,
  cliente_id     bigint references public.clientes(id),
  estado         text not null default 'pendiente'
                 check (estado in ('pendiente', 'confirmado', 'entregado', 'cancelado')),
  fecha_entrega  date,
  notas          text,
  usuario_id     uuid default auth.uid() references auth.users(id),
  creado_en      timestamptz not null default now()
);

create table public.pedido_detalle (
  id               bigint generated always as identity primary key,
  pedido_id        bigint not null references public.pedidos(id) on delete cascade,
  presentacion_id  bigint not null references public.presentaciones(id),
  cantidad         numeric(12,2) not null check (cantidad > 0),
  precio_unitario  numeric(12,2) not null check (precio_unitario >= 0)
);


-- ---------------------------------------------------------------------
-- 4. Ventas
-- ---------------------------------------------------------------------
create table public.ventas (
  id                bigint generated always as identity primary key,   -- número de venta
  cliente_id        bigint references public.clientes(id),
  pedido_id         bigint references public.pedidos(id),
  metodo_pago       text not null
                    check (metodo_pago in ('efectivo', 'transferencia', 'tarjeta', 'credito')),
  subtotal          numeric(12,2) not null default 0,
  descuento         numeric(12,2) not null default 0 check (descuento >= 0),
  total             numeric(12,2) not null default 0,
  estado            text not null default 'pagada'
                    check (estado in ('pagada', 'pendiente_pago', 'anulada')),
  usuario_id        uuid references auth.users(id),
  creado_en         timestamptz not null default now(),
  anulada_en        timestamptz,
  motivo_anulacion  text
);

create table public.venta_detalle (
  id               bigint generated always as identity primary key,
  venta_id         bigint not null references public.ventas(id) on delete cascade,
  presentacion_id  bigint not null references public.presentaciones(id),
  cantidad         numeric(12,2) not null check (cantidad > 0),
  precio_unitario  numeric(12,2) not null check (precio_unitario >= 0),
  costo_unitario   numeric(12,2) not null default 0,   -- para calcular margen después
  subtotal         numeric(12,2) generated always as (cantidad * precio_unitario) stored
);


-- ---------------------------------------------------------------------
-- 5. Kardex: cada entrada o salida de mercancía queda registrada.
--    El stock NO se guarda: se calcula sumando esta tabla.
-- ---------------------------------------------------------------------
create table public.movimientos_inventario (
  id               bigint generated always as identity primary key,
  presentacion_id  bigint not null references public.presentaciones(id),
  tipo             text not null
                   check (tipo in ('inicial', 'compra', 'venta', 'devolucion', 'ajuste')),
  cantidad         numeric(12,2) not null check (cantidad <> 0),  -- + entra, - sale
  costo_unitario   numeric(12,2),
  proveedor_id     bigint references public.proveedores(id),
  venta_id         bigint references public.ventas(id),
  nota             text,
  usuario_id       uuid references auth.users(id),
  creado_en        timestamptz not null default now()
);

create index on public.movimientos_inventario (presentacion_id);
create index on public.movimientos_inventario (venta_id);
create index on public.venta_detalle (venta_id);
create index on public.ventas (creado_en);
create index on public.presentaciones (producto_id);
create index on public.pedido_detalle (pedido_id);


-- ---------------------------------------------------------------------
-- 6. Vistas
-- ---------------------------------------------------------------------
-- Catálogo con stock calculado. security_invoker hace que respete RLS.
create view public.v_catalogo with (security_invoker = true) as
select
  pr.id,
  pr.producto_id,
  pr.sku,
  pr.codigo_barras,
  p.nombre        as producto,
  pr.nombre       as presentacion,
  m.nombre        as marca,
  c.nombre        as categoria,
  p.codigo_color,
  concat_ws(' ', m.nombre, p.nombre, p.codigo_color, pr.nombre) as etiqueta,
  pr.precio_venta,
  pr.costo,
  pr.stock_minimo,
  coalesce(s.stock, 0) as stock,
  (pr.activo and p.activo) as activo
from public.presentaciones pr
join public.productos p        on p.id = pr.producto_id
left join public.marcas m      on m.id = p.marca_id
left join public.categorias c  on c.id = p.categoria_id
left join (
  select presentacion_id, sum(cantidad) as stock
  from public.movimientos_inventario
  group by presentacion_id
) s on s.presentacion_id = pr.id;

-- Lo que hay que reponer
create view public.v_stock_bajo with (security_invoker = true) as
select * from public.v_catalogo
where activo and stock <= stock_minimo
order by stock - stock_minimo;


-- ---------------------------------------------------------------------
-- 7. Funciones de negocio (toda escritura de ventas e inventario
--    pasa por aquí, en una sola transacción)
-- ---------------------------------------------------------------------

-- Registra una venta completa y descuenta el stock.
-- p_items: [{"presentacion_id": 12, "cantidad": 2}, ...]
-- El precio se toma siempre de la base de datos, no del navegador.
create or replace function public.registrar_venta(
  p_items        jsonb,
  p_cliente_id   bigint  default null,
  p_metodo_pago  text    default 'efectivo',
  p_descuento    numeric default 0,
  p_pedido_id    bigint  default null
)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_venta_id  bigint;
  v_item      jsonb;
  v_pres      record;
  v_cantidad  numeric;
  v_stock     numeric;
  v_subtotal  numeric := 0;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no tiene productos';
  end if;

  if p_metodo_pago = 'credito' and p_cliente_id is null then
    raise exception 'Las ventas a crédito requieren un cliente';
  end if;

  -- Bloquea las presentaciones involucradas, en orden, para que dos
  -- ventas simultáneas no vendan las mismas unidades.
  perform 1
    from presentaciones
   where id in (select (e->>'presentacion_id')::bigint
                  from jsonb_array_elements(p_items) e)
   order by id
   for update;

  insert into ventas (cliente_id, pedido_id, metodo_pago, descuento, estado, usuario_id)
  values (
    p_cliente_id,
    p_pedido_id,
    p_metodo_pago,
    coalesce(p_descuento, 0),
    case when p_metodo_pago = 'credito' then 'pendiente_pago' else 'pagada' end,
    auth.uid()
  )
  returning id into v_venta_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_cantidad := (v_item->>'cantidad')::numeric;
    if v_cantidad is null or v_cantidad <= 0 then
      raise exception 'Cantidad inválida en la venta';
    end if;

    select pr.id,
           pr.precio_venta,
           pr.costo,
           (pr.activo and p.activo) as activo,
           concat_ws(' ', p.nombre, pr.nombre) as etiqueta
      into v_pres
      from presentaciones pr
      join productos p on p.id = pr.producto_id
     where pr.id = (v_item->>'presentacion_id')::bigint;

    if not found then
      raise exception 'El producto % no existe', v_item->>'presentacion_id';
    end if;
    if not v_pres.activo then
      raise exception '% está inactivo y no se puede vender', v_pres.etiqueta;
    end if;

    select coalesce(sum(cantidad), 0) into v_stock
      from movimientos_inventario
     where presentacion_id = v_pres.id;

    if v_stock < v_cantidad then
      raise exception 'Stock insuficiente de %: hay %, se piden %',
        v_pres.etiqueta, v_stock, v_cantidad;
    end if;

    insert into venta_detalle (venta_id, presentacion_id, cantidad, precio_unitario, costo_unitario)
    values (v_venta_id, v_pres.id, v_cantidad, v_pres.precio_venta, v_pres.costo);

    insert into movimientos_inventario (presentacion_id, tipo, cantidad, venta_id, usuario_id)
    values (v_pres.id, 'venta', -v_cantidad, v_venta_id, auth.uid());

    v_subtotal := v_subtotal + v_cantidad * v_pres.precio_venta;
  end loop;

  if coalesce(p_descuento, 0) > v_subtotal then
    raise exception 'El descuento no puede superar el subtotal';
  end if;

  update ventas
     set subtotal = v_subtotal,
         total    = v_subtotal - coalesce(p_descuento, 0)
   where id = v_venta_id;

  if p_pedido_id is not null then
    update pedidos set estado = 'entregado' where id = p_pedido_id;
  end if;

  return v_venta_id;
end;
$$;


-- Anula una venta y devuelve la mercancía al inventario.
create or replace function public.anular_venta(p_venta_id bigint, p_motivo text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_estado text;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if coalesce(trim(p_motivo), '') = '' then
    raise exception 'Indica el motivo de la anulación';
  end if;

  select estado into v_estado from ventas where id = p_venta_id for update;
  if not found then
    raise exception 'La venta % no existe', p_venta_id;
  end if;
  if v_estado = 'anulada' then
    raise exception 'La venta % ya está anulada', p_venta_id;
  end if;

  insert into movimientos_inventario (presentacion_id, tipo, cantidad, venta_id, nota, usuario_id)
  select presentacion_id, 'devolucion', cantidad, p_venta_id,
         'Anulación: ' || p_motivo, auth.uid()
    from venta_detalle
   where venta_id = p_venta_id;

  update ventas
     set estado = 'anulada', anulada_en = now(), motivo_anulacion = p_motivo
   where id = p_venta_id;
end;
$$;


-- Entradas y ajustes de inventario:
--   'inicial' -> conteo inicial al arrancar
--   'compra'  -> mercancía que llega del proveedor (actualiza el costo)
--   'ajuste'  -> corrección por conteo, daño o pérdida (puede ser negativo, exige nota)
create or replace function public.registrar_movimiento(
  p_presentacion_id  bigint,
  p_tipo             text,
  p_cantidad         numeric,
  p_costo_unitario   numeric default null,
  p_proveedor_id     bigint  default null,
  p_nota             text    default null
)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if not es_usuario_activo() then
    raise exception 'Usuario no autorizado';
  end if;
  if p_tipo not in ('inicial', 'compra', 'ajuste') then
    raise exception 'Tipo de movimiento no permitido: %', p_tipo;
  end if;
  if p_tipo in ('inicial', 'compra') and p_cantidad <= 0 then
    raise exception 'Las entradas deben tener cantidad positiva';
  end if;
  if p_tipo = 'ajuste' and coalesce(trim(p_nota), '') = '' then
    raise exception 'Los ajustes requieren una nota que explique el motivo';
  end if;

  insert into movimientos_inventario
    (presentacion_id, tipo, cantidad, costo_unitario, proveedor_id, nota, usuario_id)
  values
    (p_presentacion_id, p_tipo, p_cantidad, p_costo_unitario, p_proveedor_id, p_nota, auth.uid())
  returning id into v_id;

  if p_tipo = 'compra' and p_costo_unitario is not null then
    update presentaciones set costo = p_costo_unitario where id = p_presentacion_id;
  end if;

  return v_id;
end;
$$;


-- ---------------------------------------------------------------------
-- 8. Seguridad (RLS)
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  -- Maestros: los usuarios activos leen y escriben
  foreach t in array array[
    'categorias', 'marcas', 'proveedores', 'productos',
    'presentaciones', 'clientes', 'pedidos', 'pedido_detalle'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "usuarios activos gestionan" on public.%I
         for all to authenticated
         using (public.es_usuario_activo())
         with check (public.es_usuario_activo())', t);
  end loop;

  -- Transaccionales: solo lectura directa; se escriben con las funciones
  foreach t in array array[
    'perfiles', 'ventas', 'venta_detalle', 'movimientos_inventario'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "usuarios activos consultan" on public.%I
         for select to authenticated
         using (public.es_usuario_activo())', t);
  end loop;
end $$;

-- Las funciones solo las puede ejecutar un usuario con sesión iniciada
revoke execute on function public.es_usuario_activo() from public, anon;
revoke execute on function public.registrar_venta(jsonb, bigint, text, numeric, bigint) from public, anon;
revoke execute on function public.anular_venta(bigint, text) from public, anon;
revoke execute on function public.registrar_movimiento(bigint, text, numeric, numeric, bigint, text) from public, anon;

grant execute on function public.es_usuario_activo() to authenticated;
grant execute on function public.registrar_venta(jsonb, bigint, text, numeric, bigint) to authenticated;
grant execute on function public.anular_venta(bigint, text) to authenticated;
grant execute on function public.registrar_movimiento(bigint, text, numeric, numeric, bigint, text) to authenticated;


-- ---------------------------------------------------------------------
-- 9. Datos iniciales
-- ---------------------------------------------------------------------
insert into public.categorias (nombre) values
  ('Pintura base'),
  ('Barniz / transparente'),
  ('Primer / fondo'),
  ('Masillas'),
  ('Thinner y solventes'),
  ('Lijas y abrasivos'),
  ('Cinta y enmascarado'),
  ('Pistolas y herramientas'),
  ('Seguridad industrial');


-- ---------------------------------------------------------------------
-- 10. DESPUÉS de crear los 3 usuarios en Authentication > Users,
--     ejecuta esto (cambia correos y nombres):
-- ---------------------------------------------------------------------
-- insert into public.perfiles (id, nombre)
-- select id, 'Andrés' from auth.users where email = 'andres@correo.com';
-- insert into public.perfiles (id, nombre)
-- select id, 'Socio 2' from auth.users where email = 'socio2@correo.com';
-- insert into public.perfiles (id, nombre)
-- select id, 'Socio 3' from auth.users where email = 'socio3@correo.com';
