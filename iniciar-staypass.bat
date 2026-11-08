@echo off
chcp 65001 >nul
title StayPass QR - Iniciador de Ecosistema Local
cd /d "%~dp0"

echo ============================================================================
echo   StayPass QR - Iniciando Backend (:3000), Apps Web (:8081/:8082/:8083)
echo                 y Controladora Virtual ESP32 + GM65 + FAAC (:3090)
echo ============================================================================

netstat -ano | findstr ":3000 " | findstr "LISTENING" >nul
if %errorlevel% neq 0 (
    echo [1/2] Iniciando servidor API Backend en puerto 3000...
    start "StayPass Backend API (:3000)" cmd /k "cd /d ""%~dp0backend"" && node src/server.js"
) else (
    echo [1/2] Backend API (:3000) ya se encuentra en ejecucion.
)

netstat -ano | findstr ":8081 " | findstr "LISTENING" >nul
if %errorlevel% neq 0 (
    echo [2/2] Iniciando Apps Web (:8081/:8082/:8083) y Emulador FAAC (:3090)...
    start "StayPass Web & IoT (:8081-:8083, :3090)" cmd /k "cd /d ""%~dp0"" && node scripts/serve-web-apps.js"
) else (
    echo [2/2] Servidor Web (:8081/:8082/:8083) ya se encuentra en ejecucion.
)

timeout /t 3 /nobreak >nul
start "" "http://localhost:8081"
start "" "http://localhost:8082"
start "" "http://localhost:8083"

echo.
echo Todo listo. Las 3 pestanas se abrieron en tu navegador.
pause
