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

rem 3) Start the server (it prints its address and the app finds it by itself)
python main.py
pause
