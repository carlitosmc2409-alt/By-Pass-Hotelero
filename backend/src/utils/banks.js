/**
 * Bancos de Venezuela con código de 4 dígitos usado en Pago Móvil.
 * Verificar contra la lista vigente de la red interbancaria antes de producción.
 */
const BANKS = {
  '0102': 'Banco de Venezuela',
  '0104': 'Venezolano de Crédito',
  '0105': 'Mercantil',
  '0108': 'Provincial',
  '0114': 'Bancaribe',
  '0115': 'Banco Exterior',
  '0116': 'Banco Occidental de Descuento',
  '0128': 'Banco Caroní',
  '0134': 'Banesco',
  '0137': 'Sofitasa',
  '0138': 'Banco Plaza',
  '0146': 'Bangente',
  '0151': 'BFC Banco Fondo Común',
  '0156': '100% Banco',
  '0157': 'DelSur',
  '0163': 'Banco del Tesoro',
  '0166': 'Banco Agrícola de Venezuela',
  '0168': 'Bancrecer',
  '0169': 'Mi Banco',
  '0171': 'Banco Activo',
  '0172': 'Bancamiga',
  '0174': 'Banplus',
  '0175': 'Banco Bicentenario',
  '0177': 'Banfanb',
  '0191': 'Banco Nacional de Crédito (BNC)',
}

const BANK_CODES = Object.keys(BANKS)

function bankName(code) {
  return BANKS[code] || null
}

module.exports = { BANKS, BANK_CODES, bankName }
