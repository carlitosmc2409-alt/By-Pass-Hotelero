const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const path = require('path')

require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') })
const { prisma } = require('../src/config/database')
const { expireReservations, autoReleaseCleaningRooms } = require('../src/utils/cron')
const dayjs = require('dayjs')

describe('Ciclo Operativo de Habitaciones y Limpieza Automática (30 min)', () => {
  let testHotel
  let testRoom
  let testGuest

  before(async () => {
    testHotel = await prisma.hotel.findFirst({ select: { id: true } })
    testGuest = await prisma.guest.findFirst({ select: { id: true } })

    // Crear habitación exclusiva de prueba
    testRoom = await prisma.room.create({
      data: {
        hotelId: testHotel.id,
        name: 'TEST-CLEAN-999',
        type: 'STANDARD',
        pricePerHour: 10,
        pricePerNight: 50,
        currency: 'USD',
        status: 'AVAILABLE',
      },
    })
  })

  after(async () => {
    if (testRoom) {
      await prisma.reservation.deleteMany({ where: { roomId: testRoom.id } })
      await prisma.room.delete({ where: { id: testRoom.id } })
    }
    await prisma.$disconnect()
  })

  test('Al culminar la hora de reservación, la habitación pasa automáticamente a CLEANING', async () => {
    // Crear una reserva expirada en el pasado (-2 horas)
    const checkIn = dayjs().subtract(3, 'hour').toDate()
    const checkOut = dayjs().subtract(1, 'hour').toDate()

    const res = await prisma.reservation.create({
      data: {
        guestId: testGuest.id,
        roomId: testRoom.id,
        checkIn,
        checkOut,
        durationHours: 2,
        totalAmount: 20,
        status: 'ACTIVE',
      },
    })

    // Ejecutar job de expiración
    await expireReservations()

    // Comprobar que la reserva expiró y la habitación pasó a CLEANING
    const updatedRes = await prisma.reservation.findUnique({ where: { id: res.id } })
    assert.strictEqual(updatedRes.status, 'EXPIRED')

    const updatedRoom = await prisma.room.findUnique({ where: { id: testRoom.id } })
    assert.strictEqual(updatedRoom.status, 'CLEANING', 'La habitación debe pasar a CLEANING tras expirar estadía')
  })

  test('Si no han pasado 30 minutos, la habitación permanece en CLEANING', async () => {
    // La habitación acaba de entrar en CLEANING (updatedAt reciente)
    const result = await autoReleaseCleaningRooms()

    const room = await prisma.room.findUnique({ where: { id: testRoom.id } })
    assert.strictEqual(room.status, 'CLEANING', 'No debe liberarse antes de los 30 minutos')
  })

  test('Si transcurrieron 30 minutos de limpieza sin acción de la camarera, el sistema la coloca como AVAILABLE automáticamente', async () => {
    // Simular que la habitación lleva 31 minutos desocupada en CLEANING
    const pastDate = dayjs().subtract(31, 'minute').toDate()
    await prisma.$executeRawUnsafe(
      `UPDATE rooms SET "updatedAt" = $1 WHERE id = $2`,
      pastDate,
      testRoom.id
    )

    // Ejecutar el job automático
    const result = await autoReleaseCleaningRooms()
    assert.ok(result.releasedCount >= 1, 'Debe haber liberado al menos 1 habitación')

    const releasedRoom = await prisma.room.findUnique({ where: { id: testRoom.id } })
    assert.strictEqual(releasedRoom.status, 'AVAILABLE', 'La habitación debe estar AVAILABLE (Lista) automáticamente tras 30 min')
  })
})
