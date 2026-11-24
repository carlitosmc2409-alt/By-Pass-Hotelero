const { buildApp } = require('../src/config/app')

let app = null

module.exports = async (req, res) => {
  if (!app) {
    app = await buildApp()
    await app.ready()
  }
  app.server.emit('request', req, res)
}
