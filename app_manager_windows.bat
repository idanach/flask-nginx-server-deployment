@echo off
setlocal enabledelayedexpansion

:: === CONFIGURATION ===
set "INSTALLERS_DIR=%~dp0installers"
set "PYTHON_EXE=python-3.12.3-amd64.exe"
set "NSSM_ZIP=nssm-2.24.zip"
set "NGINX_ZIP=nginx-1.27.4.zip"

set "APP_NAME=AppName"
set "APP_DIR=C:\AppName"
set "VENV=%APP_DIR%\venv"
set "MODULE=source:create_app"
set "PORT=8000"
set "SERVICE_NAME=%APP_NAME%"
set "NSSM_DIR=C:\nssm"
set "NSSM_PATH=%NSSM_DIR%\nssm.exe"
set "NGINX_PATH=C:\nginx"
set "NGINX_CONF=%NGINX_PATH%\conf\nginx.conf"
set "LOGDIR=%APP_DIR%\logs"

echo.
echo [APP MANAGER - WINDOWS]
echo 0) Setup server (install Python, nginx, NSSM from installers/)
echo 1) Setup nginx config + start nginx
echo 2) Install app as service (NSSM)
echo 3) Start app
echo 4) Stop app
echo 5) Restart app
echo 6) View app status
echo 7) View app logs
echo 8) Uninstall app service
set /p choice="Enter number [0-8]: "
echo.

:: === CASE HANDLING ===

if "%choice%"=="0" (
    echo 🔧 Installing components from %INSTALLERS_DIR%...

    echo ✅ Checking for Python...
    where python >nul 2>nul
    if errorlevel 1 (
        echo Installing Python...
        "%INSTALLERS_DIR%\%PYTHON_EXE%" /quiet InstallAllUsers=1 PrependPath=1
    ) else (
        echo Python already installed.
    )

    echo ✅ Creating virtual environment...
    mkdir "%APP_DIR%" 2>nul
    mkdir "%LOGDIR%" 2>nul
    python -m venv "%VENV%"
    call "%VENV%\Scripts\activate"
    pip install --upgrade pip
    pip install waitress

    if not exist "%NSSM_PATH%" (
        echo ✅ Extracting NSSM...
        powershell -Command "Expand-Archive -Path '%INSTALLERS_DIR%\%NSSM_ZIP%' -DestinationPath '%TEMP%\nssm_extract' -Force"
        mkdir "%NSSM_DIR%" >nul 2>&1
        copy "%TEMP%\nssm_extract\nssm-2.24\win64\nssm.exe" "%NSSM_PATH%" >nul
    )

    if not exist "%NGINX_PATH%\nginx.exe" (
        echo ✅ Extracting nginx...
        powershell -Command "Expand-Archive -Path '%INSTALLERS_DIR%\%NGINX_ZIP%' -DestinationPath '%TEMP%\nginx_extract' -Force"
        move "%TEMP%\nginx_extract\nginx-1.27.4" "%NGINX_PATH%" >nul
    )

    echo ✅ Setup complete!
    goto :eof
)

if "%choice%"=="1" (
    echo Writing nginx.conf...
    > "%NGINX_CONF%" echo worker_processes 1;
    >>"%NGINX_CONF%" echo events { worker_connections 1024; };
    >>"%NGINX_CONF%" echo http {
    >>"%NGINX_CONF%" echo     include       mime.types;
    >>"%NGINX_CONF%" echo     default_type  application/octet-stream;
    >>"%NGINX_CONF%" echo     sendfile        on;
    >>"%NGINX_CONF%" echo     keepalive_timeout  65;
    >>"%NGINX_CONF%" echo     server {
    >>"%NGINX_CONF%" echo         listen       80;
    >>"%NGINX_CONF%" echo         server_name  localhost;
    >>"%NGINX_CONF%" echo         location / {
    >>"%NGINX_CONF%" echo             proxy_pass http://127.0.0.1:%PORT%;
    >>"%NGINX_CONF%" echo             proxy_set_header Host \$host;
    >>"%NGINX_CONF%" echo             proxy_set_header X-Real-IP \$remote_addr;
    >>"%NGINX_CONF%" echo             proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    >>"%NGINX_CONF%" echo         }
    >>"%NGINX_CONF%" echo     }
    >>"%NGINX_CONF%" echo }

    echo Starting nginx...
    start "" "%NGINX_PATH%\nginx.exe"
    goto :eof
)

if "%choice%"=="2" (
    echo Installing %APP_NAME% as Windows service using NSSM...
    "%NSSM_PATH%" install "%SERVICE_NAME%" "%VENV%\Scripts\python.exe" -m waitress --listen=*:8000 %MODULE%
    "%NSSM_PATH%" set "%SERVICE_NAME%" AppDirectory "%APP_DIR%"
    "%NSSM_PATH%" set "%SERVICE_NAME%" AppStdout "%LOGDIR%\out.log"
    "%NSSM_PATH%" set "%SERVICE_NAME%" AppStderr "%LOGDIR%\err.log"
    "%NSSM_PATH%" set "%SERVICE_NAME%" Start SERVICE_AUTO_START
    goto :eof
)

if "%choice%"=="3" (
    echo Starting service...
    sc start "%SERVICE_NAME%"
    goto :eof
)

if "%choice%"=="4" (
    echo Stopping service...
    sc stop "%SERVICE_NAME%"
    goto :eof
)

if "%choice%"=="5" (
    echo Restarting service...
    sc stop "%SERVICE_NAME%"
    timeout /t 3 /nobreak >nul
    sc start "%SERVICE_NAME%"
    goto :eof
)

if "%choice%"=="6" (
    echo Checking service status...
    sc query "%SERVICE_NAME%"
    goto :eof
)

if "%choice%"=="7" (
    echo Viewing logs (CTRL+C to exit)...
    if exist "%LOGDIR%\out.log" (
        powershell Get-Content "%LOGDIR%\out.log" -Wait
    ) else (
        echo No logs found at %LOGDIR%\out.log
    )
    goto :eof
)

if "%choice%"=="8" (
    echo Uninstalling service...
    "%NSSM_PATH%" remove "%SERVICE_NAME%" confirm
    goto :eof
)

echo ❌ Invalid choice.
