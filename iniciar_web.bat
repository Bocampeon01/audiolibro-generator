@echo off
rem Inicia el generador web. 0.0.0.0 = accesible desde el celular en el mismo WiFi
rem (Windows puede preguntar si permitir Python en el firewall: acepta "Redes privadas").
cd /d "%~dp0"
echo Abriendo http://localhost:8000 ...
start "" http://localhost:8000
.venv\Scripts\python -m uvicorn web.backend.main:app --host 0.0.0.0 --port 8000
pause
