/**
 * Servidor unificado de aplicaciones Web compiladas del ecosistema StayPass QR:
 *  - Puerto 8081: App del Huésped (mobile_app/build/web)
 *  - Puerto 8082: Panel del Propietario (owner_panel/build/web)
 *  - Puerto 8083: Simulador IoT Lector QR de Puerta y Garaje (door_scanner/)
 */
const http = require('http')
const fs = require('fs')
const path = require('path')

const ROOT = path.resolve(__dirname, '..')

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
}

function startStaticServer(name, baseDir, port) {
  const server = http.createServer((req, res) => {
    const cleanUrl = decodeURIComponent((req.url || '/').split('?')[0])
    const relPath = cleanUrl === '/' ? 'index.html' : cleanUrl.replace(/^\/+/, '')
    const resolved = path.resolve(baseDir, relPath)

    // Evitar path traversal fuera de baseDir
    if (!resolved.startsWith(baseDir)) {
      res.writeHead(403)
      res.end('Forbidden')
      return
    }

    fs.stat(resolved, (err, stats) => {
      const targetFile = !err && stats.isFile()
        ? resolved
        : path.join(baseDir, 'index.html')

      fs.readFile(targetFile, (readErr, data) => {
        if (readErr) {
          res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' })
          res.end(`Recurso no encontrado en ${name}`)
          return
        }
        const ext = path.extname(targetFile).toLowerCase()
        const contentType = MIME_TYPES[ext] || 'application/octet-stream'
        res.writeHead(200, {
          'Content-Type': contentType,
          'Cache-Control': 'no-cache',
        })
        res.end(data)
      })
    })
  })

  server.listen(port, '0.0.0.0', () => {
    console.log(`✅ ${name} disponible en http://localhost:${port}`)
  })
}

startStaticServer(
  'App del Huésped (StayPass QR)',
  path.join(ROOT, 'mobile_app', 'build', 'web'),
  8081
)
startStaticServer(
  'Panel del Propietario (StayPass Panel)',
  path.join(ROOT, 'owner_panel', 'build', 'web'),
  8082
)
startStaticServer(
  'Simulador Lector QR de Puerta y Garaje',
  path.join(ROOT, 'door_scanner'),
  8083
)
