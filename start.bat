@echo off
echo Starting EpiSignal...
echo.
echo Make sure you have added your API keys to server\.env
echo.

start "EpiSignal Server" cmd /k "cd /d %~dp0server && node index.js"
timeout /t 2 /nobreak > nul
start "EpiSignal Client" cmd /k "cd /d %~dp0client && npm run dev"

echo.
echo Server: http://localhost:3001
echo Client: http://localhost:5173
echo.
pause
