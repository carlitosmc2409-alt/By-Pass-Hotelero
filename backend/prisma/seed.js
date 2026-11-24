/**
 * Seed de desarrollo — crea datos de prueba para el piloto Venezuela
 * Ejecutar: npm run db:seed
 */

const { PrismaClient } = require('@prisma/client')
const bcrypt = require('bcryptjs')
const prisma = new PrismaClient()

async function main() {
  console.log('🌱 Iniciando seed...')

  // Propietario de prueba
  const ownerPassword = await bcrypt.hash('Admin@12345', 12)
  const owner = await prisma.owner.upsert({
    where: { email: 'propietario@test.com' },
    update: {},
    create: {
      fullName: 'Carlos Pérez',
      email: 'propietario@test.com',
      phone: '+584121234567',
      cedula: 'V-12345678',
      passwordHash: ownerPassword,
    },
  })
  console.log('✅ Propietario:', owner.email)

  // Hotel de prueba (con datos receptores de Pago Móvil en Banco de Venezuela)
  const paymentInfo = {
    bank: '0102',
    bankName: 'Banco de Venezuela',
    phone: '+584121234567',
    idNumber: 'J-50123456-7',
    holderName: 'Inversiones La Brisa C.A.',
  }
  const staffPinHash = await bcrypt.hash('1234', 10)
  const receptionPassHash = await bcrypt.hash('Recepcion2026*', 10)
  const defaultSettings = {
    faac: {
      enabled: true,
      model: 'FAAC 615 BPR / Placa E615',
      entryDeviceId: 'faac-entrada-1',
      exitDeviceId: 'faac-salida-1',
      contactType: 'NO (OPEN-A + GND)',
      pulseDurationMs: 1000,
      exitGraceMinutes: 15,
      relayWebhookUrl: 'http://localhost:3090/rpc/pulse',
    },
    cleaningStaff: [
      {
        id: '00000000-0000-4000-8000-000000000901',
        name: 'Elena Turno Nocturno',
        alias: 'camarera1',
        pinHash: staffPinHash,
        role: 'CLEANING',
        active: true,
        createdAt: new Date().toISOString(),
      },
    ],
    receptionStaff: [
      {
        id: '00000000-0000-4000-8000-000000000902',
        name: 'Juan Asistencia y Recepción',
        username: 'juan.recepcion',
        email: 'juan.recepcion@hotellabrisa.com',
        phone: '+584141234567',
        passwordHash: receptionPassHash,
        role: 'RECEPTIONIST',
        active: true,
        createdAt: new Date().toISOString(),
      },
    ],
  }
  const hotelCoverPhoto =
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1000&q=80'
  const hotelGalleryPhotos = [
    hotelCoverPhoto,
    'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=1000&q=80',
    'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=1000&q=80',
  ]

  const hotel = await prisma.hotel.upsert({
    where: { slug: 'motel-la-brisa-caracas' },
    update: {
      paymentInfo,
      settings: defaultSettings,
      coverPhoto: hotelCoverPhoto,
      photos: hotelGalleryPhotos,
    },
    create: {
      ownerId: owner.id,
      name: 'Motel La Brisa',
      slug: 'motel-la-brisa-caracas',
      address: 'Av. Principal, Chacao',
      city: 'Caracas',
      state: 'Venezuela',
      latitude: 10.4806,
      longitude: -66.9036,
      description: 'Disfruta con total privacidad.',
      coverPhoto: hotelCoverPhoto,
      photos: hotelGalleryPhotos,
      status: 'ACTIVE',
      paymentInfo,
      settings: defaultSettings,
    },
  })
  console.log('✅ Hotel:', hotel.name)

  // Habitaciones
  // Limpieza de habitaciones de seeds anteriores con IDs no-UUID
  await prisma.room.deleteMany({ where: { id: { startsWith: 'seed-room-' } } })

  // IDs UUID v4 fijos para que el seed sea idempotente
  const rooms = [
    {
      id: '00000000-0000-4000-8000-000000000101',
      name: '101',
      type: 'STANDARD',
      description: 'Habitación acogedora con iluminación cálida, Smart TV, estacionamiento privado directo y servicio por pasaplatos.',
      pricePerHour: 10,
      pricePerNight: 50,
      amenities: ['WiFi', 'TV', 'Aire acondicionado'],
      photos: [
        'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=900&q=80',
      ],
      sortOrder: 1,
    },
    {
      id: '00000000-0000-4000-8000-000000000102',
      name: '102',
      type: 'DELUXE',
      description: 'Suite Deluxe con bañera de hidromasaje, cama Queen de lujo, ambiente insonorizado y acceso vehicular con código QR.',
      pricePerHour: 15,
      pricePerNight: 70,
      amenities: ['WiFi', 'TV', 'Aire acondicionado', 'Jacuzzi'],
      photos: [
        'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=900&q=80',
      ],
      sortOrder: 2,
    },
    {
      id: '00000000-0000-4000-8000-000000000103',
      name: 'Suite A',
      type: 'SUITE',
      description: 'Nuestra mejor Suite Boutique con Jacuzzi VIP climatizado, cama King Size, minibar completo y garaje privado.',
      pricePerHour: 25,
      pricePerNight: 100,
      amenities: ['WiFi', 'TV', 'Aire acondicionado', 'Jacuzzi', 'Minibar'],
      photos: [
        'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1560448204-603b3fc33ddc?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=900&q=80',
      ],
      sortOrder: 3,
    },
  ]

  for (const roomData of rooms) {
    await prisma.room.upsert({
      where: { id: roomData.id },
      update: {
        description: roomData.description,
        photos: roomData.photos,
      },
      create: {
        hotelId: hotel.id,
        currency: 'USD',
        status: 'AVAILABLE',
        maxGuests: 2,
        ...roomData,
      },
    })
    console.log(`✅ Habitación: ${roomData.name}`)
  }

  // Huésped de prueba (con datos de pago frecuente cifrados)
  const guestPassword = await bcrypt.hash('Guest@12345', 12)
  const { hashValue } = require('../src/utils/crypto')
  const { encryptField } = require('../src/utils/fieldCrypto')
  const phone = '+584129876543'
  const cedula = 'V-20123456'
  const guest = await prisma.guest.upsert({
    where: { phone },
    update: {
      paymentBank: '0102',
      paymentCedula: encryptField(cedula),
      paymentPhone: encryptField(phone),
    },
    create: {
      fullName: 'María González',
      phone,
      phoneHash: hashValue(phone),
      cedula,
      paymentBank: '0102',
      paymentCedula: encryptField(cedula),
      paymentPhone: encryptField(phone),
      passwordHash: guestPassword,
      isVerified: true,
    },
  })
  console.log('✅ Huésped:', guest.fullName)

  console.log('\n🎉 Seed completado exitosamente!')
  console.log('────────────────────────────────')
  console.log('Propietario → propietario@test.com / Admin@12345')
  console.log('Huésped     → +584129876543 / Guest@12345')
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect())
