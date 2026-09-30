// Configuración compartida por todas las pantallas.
// Supabase > Project Settings > API. La anon key es pública por diseño:
// la protección real son las políticas RLS del script SQL.
// NUNCA pongas aquí la service_role key.
window.APP_CONFIG = {
  SUPABASE_URL: 'https://TU-PROYECTO.supabase.co',
  SUPABASE_ANON_KEY: 'TU_ANON_KEY_PUBLICA',
  NOMBRE_TIENDA: 'Pinturas',

  // Datos que salen en el recibo (deja vacío lo que no quieras mostrar)
  NEGOCIO: {
    NIT: '',
    DIRECCION: '',
    TELEFONO: '',
    PIE: 'Gracias por su compra'
  },
  ANCHO_RECIBO: '80mm'   // '58mm' para impresoras térmicas pequeñas
};
