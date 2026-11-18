@echo off
setlocal
cd /d "%~dp0"

set "LAUNCHER=AssetDesk_Launcher.exe"
if /i "%~1"=="consola" set "LAUNCHER=AssetDesk_Launcher_consola.exe"
if not exist "%LAUNCHER%" goto nolauncher

echo [1/3] Compilando la version web de Flutter...
call flutter build web --release
if errorlevel 1 goto error

echo [2/3] Empaquetando los archivos...
if exist web.zip del /q web.zip
tar -a -c -f web.zip -C build\web .
if errorlevel 1 goto error

echo [3/3] Creando AssetDesk.exe...
if exist AssetDesk.exe del /q AssetDesk.exe
copy /b /y "%LAUNCHER%" + web.zip AssetDesk.exe >nul
if errorlevel 1 goto error
del /q web.zip

echo.
echo LISTO. Se creo:  %~dp0AssetDesk.exe
echo Ese archivo es el que le entregas al usuario: al dar doble clic abre el sistema en el navegador (localhost), sin ventanas negras.
goto fin

:nolauncher
echo ERROR: falta %LAUNCHER% junto a este archivo.
goto error

:error
echo.
echo Hubo un error. Revisa el mensaje de arriba.
pause
exit /b 1

:fin
pause
