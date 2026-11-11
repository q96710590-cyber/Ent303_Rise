@echo off
setlocal
cd /d "%~dp0"
set "RISE_PY=%~dp0.venv\Scripts\pythonw.exe"
if not exist "%RISE_PY%" set "RISE_PY=%~dp0..\..\code\.venv\Scripts\pythonw.exe"
if exist "%RISE_PY%" (
  start "" "%RISE_PY%" "%~dp0app.py"
  exit /b 0
)
echo Please install Python 3.12, then run these commands in this folder:
echo py -3.12 -m venv .venv
echo .venv\Scripts\python.exe -m pip install -r requirements.txt
echo Then double-click this launcher again.
pause
