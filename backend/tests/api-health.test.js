const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const path = require('path')

require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') })
const { buildApp } = require('../src/config/app')

describe('Integración HTTP Fastify', () => {
  let app

  before(async () => {
    app = await buildApp()
  })

  after(async () => {
    await app.close()
  })

  test('GET /health retorna 200 con status: ok', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/health',
    })

    assert.strictEqual(response.statusCode, 200)
    const json = response.json()
    assert.strictEqual(json.status, 'ok')
    assert.ok(json.timestamp)
  })

  test('Ruta inexistente retorna 404 estructurado', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/api/v1/ruta-inexistente-xyz',
    })

    assert.strictEqual(response.statusCode, 404)
    const json = response.json()
    assert.strictEqual(json.statusCode, 404)
    assert.strictEqual(json.error, 'Not Found')
  })
})
