@echo off
rem Saver backend: double-click to start. Close this window to stop.
cd /d "%~dp0"

rem 1) Create a private Python environment the first time
if not exist .venv (
    echo Creating Python environment...
    py -m venv .venv
)
call .venv\Scripts\activate.bat

rem 2) Install packages, and always update yt-dlp (sites change often)
pip install -q -r requirements.txt
pip install -q -U yt-dlp

rem 3) Show this PCs IP so you can type it in the app
echo.
echo Your PC address (use the Wi-Fi one in the Saver app):
ipconfig | findstr /i "IPv4"
echo Example in app: http://YOUR-IP:8000
echo.

rem 4) Start the server for all devices on your Wi-Fi
uvicorn main:app --host 0.0.0.0 --port 8000
pause
