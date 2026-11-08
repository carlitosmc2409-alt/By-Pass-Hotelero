/**
 * Servidor unificado de aplicaciones Web compiladas + Portal de Descarga APK por Wi-Fi:
 *  - Puerto 8081: App del Huésped (mobile_app/build/web)
 *  - Puerto 8082: Panel del Propietario (owner_panel/build/web)
 *  - Puerto 8083: Simulador IoT Lector QR (door_scanner/) + /descargar (Descarga directa APK con QR)
 *  - Puerto 3090: Controladora Virtual ESP32 + Lector GM65 + FAAC
 */
const http = require('http')
const fs = require('fs')
const os = require('os')
const path = require('path')

const ROOT = path.resolve(__dirname, '..')
let QRCode = null
try {
  QRCode = require(path.join(ROOT, 'backend', 'node_modules', 'qrcode'))
} catch (_) {}

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
  '.apk': 'application/vnd.android.package-archive',
}

const APK_CATALOG = {
  'staypass-clientes-arm64.apk': {
    label: 'StayPass QR · App Clientes (Android 64-bit)',
    candidates: [
      path.join(ROOT, 'mobile_app', 'build', 'app', 'outputs', 'flutter-apk', 'app-arm64-v8a-release.apk'),
      path.join(ROOT, 'mobile_app', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
      path.join(ROOT, 'mobile_app', 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk'),
    ],
  },
  'staypass-propietario-arm64.apk': {
    label: 'StayPass Panel · Propietario + Puente BDV (Android 64-bit)',
    candidates: [
      path.join(ROOT, 'owner_panel', 'build', 'app', 'outputs', 'flutter-apk', 'app-arm64-v8a-release.apk'),
      path.join(ROOT, 'owner_panel', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
      path.join(ROOT, 'owner_panel', 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk'),
    ],
  },
  'staypass-clientes-arm32.apk': {
    label: 'StayPass QR · Clientes (Android 32-bit antiguos)',
    candidates: [
      path.join(ROOT, 'mobile_app', 'build', 'app', 'outputs', 'flutter-apk', 'app-armeabi-v7a-release.apk'),
    ],
  },
  'staypass-propietario-arm32.apk': {
    label: 'StayPass Panel · Propietario (Android 32-bit antiguos)',
    candidates: [
      path.join(ROOT, 'owner_panel', 'build', 'app', 'outputs', 'flutter-apk', 'app-armeabi-v7a-release.apk'),
    ],
  },
}

function detectLanIp() {
  const nets = os.networkInterfaces()
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal && !net.address.startsWith('169.254.')) {
        return net.address
      }
    }
  }
  return 'localhost'
}

function resolveApkInfo(slug) {
  const entry = APK_CATALOG[slug]
  if (!entry) return null
  for (const filePath of entry.candidates) {
    try {
      const st = fs.statSync(filePath)
      if (st.isFile()) {
        return {
          slug,
          label: entry.label,
          filePath,
          sizeBytes: st.size,
          sizeMb: (st.size / (1024 * 1024)).toFixed(2),
          isRelease: filePath.includes('release'),
        }
      }
    } catch (_) {}
  }
  return null
}

async function renderApkDownloadPage(req, res, port) {
  const lanIp = detectLanIp()
  const portalUrl = `http://${lanIp}:${port}/descargar`
  let qrDataUrl = ''
  if (QRCode) {
    try {
      qrDataUrl = await QRCode.toDataURL(portalUrl, {
        width: 240,
        margin: 2,
        color: { dark: '#09090e', light: '#ffffff' },
      })
    } catch (_) {}
  }

  const guest64 = resolveApkInfo('staypass-clientes-arm64.apk')
  const owner64 = resolveApkInfo('staypass-propietario-arm64.apk')
  const guest32 = resolveApkInfo('staypass-clientes-arm32.apk')
  const owner32 = resolveApkInfo('staypass-propietario-arm32.apk')

  const cardHtml = (info, accent, subtitle) => {
    if (!info) return ''
    return `
      <div style="background:#151927;border:1px solid rgba(255,255,255,0.1);border-radius:18px;padding:18px;margin-bottom:14px;">
        <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;">
          <strong style="font-size:16px;color:#f8fafc;">${info.label}</strong>
          <span style="background:rgba(16,185,129,0.16);color:#10b981;padding:4px 10px;border-radius:999px;font-size:12px;font-weight:800;">
            ${info.sizeMb} MB · ${info.isRelease ? 'RELEASE LIGERO' : 'DEBUG'}
          </span>
        </div>
        <p style="color:#94a3b8;font-size:13px;margin:8px 0 14px 0;line-height:1.45;">${subtitle}</p>
        <a href="/apks/${info.slug}" style="display:inline-block;text-decoration:none;background:${accent};color:#07080d;font-weight:800;padding:12px 18px;border-radius:12px;font-size:14px;">
          ⬇️ Descargar APK (${info.sizeMb} MB)
        </a>
      </div>
    `
  }

  const html = `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>StayPass QR · Descargar APKs en tu Celular</title>
</head>
<body style="margin:0;padding:22px;font-family:system-ui,-apple-system,sans-serif;background:#07080d;color:#f8fafc;">
  <div style="max-width:780px;margin:0 auto;">
    <div style="background:#10131e;border:1px solid rgba(229,184,105,0.35);border-radius:22px;padding:24px;margin-bottom:20px;display:flex;flex-wrap:wrap;gap:22px;align-items:center;justify-content:space-between;">
      <div style="flex:1;min-width:250px;">
        <div style="color:#e5b869;font-size:12px;font-weight:800;letter-spacing:1px;text-transform:uppercase;">Descarga Directa por Wi-Fi Local</div>
        <h1 style="margin:6px 0 10px 0;font-size:24px;">Instala StayPass en tu Android</h1>
        <p style="margin:0 0 10px 0;color:#94a3b8;font-size:13.5px;line-height:1.5;">
          Conecta tu celular a la misma red Wi-Fi de esta PC y escanea el código QR (o abre <strong>${portalUrl}</strong> en el navegador del teléfono).
        </p>
        <div style="font-size:12px;color:#38bdf8;background:rgba(56,189,248,0.12);padding:8px 12px;border-radius:10px;display:inline-block;">
          📡 Preconfiguradas para conectar automáticamente a tu servidor API en <strong>http://${lanIp}:3000/api/v1</strong>
        </div>
      </div>
      ${qrDataUrl ? `<div style="background:#fff;padding:10px;border-radius:16px;text-align:center;"><img src="${qrDataUrl}" alt="QR Descarga" style="width:165px;height:165px;display:block;" /><div style="color:#09090e;font-size:11px;font-weight:800;margin-top:4px;">Escanéame con el celular</div></div>` : ''}
    </div>

    ${cardHtml(
      guest64,
      '#e5b869',
      'App para huéspedes: catálogo anónimo, cotización Bs. BCV, Pago Móvil BDV Cero-Clics, Llave QR de alto contraste, apertura de Barrera FAAC desde el auto y Modo Camuflaje Calculadora (PIN 2409=).'
    )}
    ${cardHtml(
      owner64,
      '#38bdf8',
      'App ejecutiva para el dueño y personal de limpieza: mapa de suites en vivo, Agente Lector Nativo de notificaciones BDV en 2do plano (NotificationListenerService), control de barreras FAAC y tablero Cero Finanzas.'
    )}

    ${guest32 || owner32 ? `
      <details style="margin-top:16px;color:#94a3b8;font-size:13px;">
        <summary style="cursor:pointer;padding:8px 0;">¿Celular Android antiguo de 32 bits (armeabi-v7a)?</summary>
        <div style="margin-top:10px;">
          ${cardHtml(guest32, '#94a3b8', 'Versión compatible con procesadores ARM de 32 bits.')}
          ${cardHtml(owner32, '#94a3b8', 'Versión compatible con procesadores ARM de 32 bits.')}
        </div>
      </details>
    ` : ''}
  </div>
</body>
</html>`

  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
  })
  res.end(html)
}

function startStaticServer(name, baseDir, port, { enableApkPortal = false } = {}) {
  const server = http.createServer(async (req, res) => {
    const cleanUrl = decodeURIComponent((req.url || '/').split('?')[0])

    if (enableApkPortal && (cleanUrl === '/descargar' || cleanUrl === '/apks')) {
      return renderApkDownloadPage(req, res, port)
    }

    if (enableApkPortal && cleanUrl.startsWith('/apks/')) {
      const slug = cleanUrl.replace('/apks/', '').trim()
      const info = resolveApkInfo(slug)
      if (!info) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' })
        res.end('APK no encontrado')
        return
      }
      res.writeHead(200, {
        'Content-Type': 'application/vnd.android.package-archive',
        'Content-Length': info.sizeBytes,
        'Content-Disposition': `attachment; filename="${info.slug}"`,
        'Cache-Control': 'no-store',
      })
      fs.createReadStream(info.filePath).pipe(res)
      return
    }

    const relPath = cleanUrl === '/' ? 'index.html' : cleanUrl.replace(/^\/+/, '')
    const resolved = path.resolve(baseDir, relPath)

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

  // Dual-stack (::1 + 127.0.0.1 + LAN Wi-Fi)
  server.listen(port, () => {
    console.log(`✅ ${name} disponible en http://localhost:${port}`)
    if (enableApkPortal) {
      console.log(`📲 Portal Descarga APK Wi-Fi listo en http://${detectLanIp()}:${port}/descargar`)
    }
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
  8083,
  { enableApkPortal: true }
)

// Iniciar también la Controladora Virtual ESP32 + Lector Óptico GM65 + Relé FAAC (:3090)
try {
  const { startVirtualFaacController } = require(
    path.join(ROOT, 'hardware_iot', 'virtual_faac_controller.js')
  )
  startVirtualFaacController(3090)
} catch (err) {
  console.warn('⚠️ No se pudo iniciar el emulador ESP32 FAAC (:3090):', err.message)
}
