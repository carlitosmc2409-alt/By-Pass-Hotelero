const { handleHotelIcal, handleRoomIcal } = require('./integrations.controller')

async function integrationsRoutes(fastify) {
  // Feed iCal público para suscripción por Booking.com / Airbnb / Google Calendar
  fastify.get('/ical/:hotelId.ics', handleHotelIcal)
  fastify.get('/ical/:hotelId/:roomId.ics', handleRoomIcal)
}

module.exports = integrationsRoutes
