const http = require('http')
const fs = require('fs')
const path = require('path')

const PORT = Number(process.env.PORT || 8083)
const INDEX_PATH = path.join(__dirname, 'index.html')

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ status: 'ok', service: 'door_scanner' }))
    return
  }

  fs.readFile(INDEX_PATH, (err, content) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' })
      res.end('Error cargando terminal QR')
      return
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
    res.end(content)
  })
})

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚪 Simulador Lector QR de Puerta activo en http://localhost:${PORT}`)
})
