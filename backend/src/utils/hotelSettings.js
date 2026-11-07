const DEFAULT_FAAC_CONFIG = {
  enabled: true,
  model: 'FAAC 615 BPR / Placa E615',
  entryDeviceId: 'faac-entrada-1',
  exitDeviceId: 'faac-salida-1',
  contactType: 'NO (OPEN-A + GND)',
  pulseDurationMs: 1000,
  exitGraceMinutes: 15,
  relayWebhookUrl: 'http://localhost:3090/rpc/pulse',
}

const DEFAULT_ROOM_SERVICE_MENU = [
  {
    id: 'agua-x2',
    name: 'Agua Mineral Fría (x2)',
    category: 'BEBIDAS',
    priceUsd: 3,
    description: 'Dos botellas de 500 ml entregadas por esclusa privada.',
    available: true,
  },
  {
    id: 'refrescos-hielo',
    name: 'Pack Refrescos + Cubeta de Hielo',
    category: 'BEBIDAS',
    priceUsd: 5,
    description: 'Dos refrescos en lata más cubeta térmica sellada.',
    available: true,
  },
  {
    id: 'combo-snacks',
    name: 'Combo Snacks Nocturno',
    category: 'SNACKS',
    priceUsd: 8,
    description: 'Mix salado gourmet, chocolates e hidratación para dos.',
    available: true,
  },
  {
    id: 'kit-discreto',
    name: 'Kit Íntimo & Cuidado Personal',
    category: ' BIENESTAR',
    priceUsd: 10,
    description: 'Empaque neutro sellado entregado sin contacto en pasaplatos.',
    available: true,
  },
  {
    id: 'espumante-vip',
    name: 'Botella Espumante Fría + 2 Copas',
    category: 'VIP',
    priceUsd: 22,
    description: 'Servicio frío listo en esclusa privada de tu suite.',
    available: true,
  },
]

function normalizeHotelSettings(rawSettings) {
  const base = rawSettings && typeof rawSettings === 'object' && !Array.isArray(rawSettings)
    ? rawSettings
    : {}

  const faac = {
    ...DEFAULT_FAAC_CONFIG,
    ...(base.faac && typeof base.faac === 'object' ? base.faac : {}),
  }

  const roomServiceMenu = Array.isArray(base.roomServiceMenu) && base.roomServiceMenu.length > 0
    ? base.roomServiceMenu
    : DEFAULT_ROOM_SERVICE_MENU

  const cleaningStaff = Array.isArray(base.cleaningStaff)
    ? base.cleaningStaff
    : []

  return {
    ...base,
    faac,
    roomServiceMenu,
    cleaningStaff,
  }
}

function sanitizeStaffList(cleaningStaff = []) {
  return cleaningStaff.map(({ pinHash, ...rest }) => rest)
}

module.exports = {
  DEFAULT_FAAC_CONFIG,
  DEFAULT_ROOM_SERVICE_MENU,
  normalizeHotelSettings,
  sanitizeStaffList,
}
