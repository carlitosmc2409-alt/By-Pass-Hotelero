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

  // Hotel de prueba
  const hotel = await prisma.hotel.upsert({
    where: { slug: 'motel-la-brisa-caracas' },
    update: {},
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
      status: 'ACTIVE',
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
      pricePerHour: 10,
      pricePerNight: 50,
      amenities: ['WiFi', 'TV', 'Aire acondicionado'],
      sortOrder: 1,
    },
    {
      id: '00000000-0000-4000-8000-000000000102',
      name: '102',
      type: 'DELUXE',
      pricePerHour: 15,
      pricePerNight: 70,
      amenities: ['WiFi', 'TV', 'Aire acondicionado', 'Jacuzzi'],
      sortOrder: 2,
    },
    {
      id: '00000000-0000-4000-8000-000000000103',
      name: 'Suite A',
      type: 'SUITE',
      pricePerHour: 25,
      pricePerNight: 100,
      amenities: ['WiFi', 'TV', 'Aire acondicionado', 'Jacuzzi', 'Minibar'],
      sortOrder: 3,
    },
  ]

  for (const roomData of rooms) {
    await prisma.room.upsert({
      where: { id: roomData.id },
      update: {},
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

  // Huésped de prueba
  const guestPassword = await bcrypt.hash('Guest@12345', 12)
  const { hashValue } = require('../src/utils/crypto')
  const phone = '+584129876543'
  const guest = await prisma.guest.upsert({
    where: { phone },
    update: {},
    create: {
      fullName: 'María González',
      phone,
      phoneHash: hashValue(phone),
      cedula: 'V-20123456',
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
