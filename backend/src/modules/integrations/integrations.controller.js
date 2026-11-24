const { prisma } = require('../../config/database')

function formatIcalDate(date) {
  const d = new Date(date)
  return d.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
}

/**
 * Genera contenido estándar iCalendar (RFC 5545)
 */
function buildIcsFeed({ hotel, room = null, reservations }) {
  const calName = room
    ? `StayPass - ${hotel.name} (Suite ${room.name})`
    : `StayPass - ${hotel.name} (Todas las suites)`

  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//StayPass PMS//Channel Sync iCal 1.0//ES',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${calName}`,
    'X-WR-TIMEZONE:UTC',
  ]

  const nowIcal = formatIcalDate(new Date())

  for (const res of reservations) {
    const roomName = res.room?.name || 'Suite'
    const start = formatIcalDate(res.checkIn)
    const end = formatIcalDate(res.checkOut)
    const uid = `res-${res.id}@staypass.hotel`

    lines.push(
      'BEGIN:VEVENT',
      `UID:${uid}`,
      `DTSTAMP:${nowIcal}`,
      `DTSTART:${start}`,
      `DTEND:${end}`,
      `SUMMARY:Ocupado - Suite ${roomName} (StayPass Direct)`,
      `DESCRIPTION:Reserva confirmada en StayPass PMS (${res.status}). Bloqueado para sincronización de canales (Booking/Airbnb).`,
      'STATUS:CONFIRMED',
      'END:VEVENT'
    )
  }

  lines.push('END:VCALENDAR')
  return lines.join('\r\n')
}

// GET /api/v1/integrations/ical/:hotelId.ics
async function handleHotelIcal(request, reply) {
  const { hotelId } = request.params
  const hotel = await prisma.hotel.findUnique({
    where: { id: hotelId },
    select: { id: true, name: true, slug: true },
  })

  if (!hotel) {
    return reply.status(404).send({ message: 'Hotel no encontrado' })
  }

  const reservations = await prisma.reservation.findMany({
    where: {
      room: { hotelId },
      status: { in: ['ACTIVE', 'PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] },
      checkOut: { gte: new Date() },
    },
    include: {
      room: { select: { id: true, name: true } },
    },
    orderBy: { checkIn: 'asc' },
  })

  const icsData = buildIcsFeed({ hotel, reservations })

  reply.header('Content-Type', 'text/calendar; charset=utf-8')
  reply.header('Content-Disposition', `inline; filename="${hotel.slug || 'hotel'}-reservations.ics"`)
  return reply.send(icsData)
}

// GET /api/v1/integrations/ical/:hotelId/:roomId.ics
async function handleRoomIcal(request, reply) {
  const { hotelId, roomId } = request.params
  const hotel = await prisma.hotel.findUnique({
    where: { id: hotelId },
    select: { id: true, name: true, slug: true },
  })
  if (!hotel) return reply.status(404).send({ message: 'Hotel no encontrado' })

  const room = await prisma.room.findFirst({
    where: { id: roomId, hotelId },
    select: { id: true, name: true },
  })
  if (!room) return reply.status(404).send({ message: 'Habitación no encontrada' })

  const reservations = await prisma.reservation.findMany({
    where: {
      roomId,
      status: { in: ['ACTIVE', 'PENDING_PAYMENT', 'PAYMENT_PENDING_REVIEW'] },
      checkOut: { gte: new Date() },
    },
    include: {
      room: { select: { id: true, name: true } },
    },
    orderBy: { checkIn: 'asc' },
  })

  const icsData = buildIcsFeed({ hotel, room, reservations })

  reply.header('Content-Type', 'text/calendar; charset=utf-8')
  reply.header('Content-Disposition', `inline; filename="room-${room.name}-reservations.ics"`)
  return reply.send(icsData)
}

module.exports = {
  handleHotelIcal,
  handleRoomIcal,
}
