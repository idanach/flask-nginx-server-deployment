@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: App Manager for Windows
:: ============================================================================
:: PREREQUISITES:
:: 1. Run this script as an Administrator. It will try to self-elevate.
:: 2. Create an "installers" folder in the same directory as this script.
:: 3. Place Python, Nginx (zip), and NSSM (zip) in the "installers" folder.
:: ============================================================================


:: === CONFIGURATION ===
set "DOMAIN=domain.com"
set "APP_NAME=AppName"
set "PORT=8000"

set "EMAIL=admin@%DOMAIN%"

set "ACTIVE_DRIVE=C:"

:: --- Paths for Existing SSL Certificates ---
set "EXISTING_CERT_PATH=%ACTIVE_DRIVE%\certs\%DOMAIN%\fullchain.pem"
set "EXISTING_KEY_PATH=%ACTIVE_DRIVE%\certs\%DOMAIN%\privkey.key"

set "APP_DIR=%ACTIVE_DRIVE%\%APP_NAME%"
set "VENV_PATH=%APP_DIR%\venv"
set "MODULE=source:create_app"
set "LOG_DIR=%APP_DIR%\logs"

set "INSTALLERS_DIR=%~dp0installers"
set "NGINX_DIR=%ACTIVE_DRIVE%\nginx"
set "NSSM_DIR=%ACTIVE_DRIVE%\nssm"
set "CERTBOT_DIR=%ACTIVE_DRIVE%\Certbot"
set "NSSM_EXE=%NSSM_DIR%\nssm.exe"

set "APP_SERVICE_NAME=%APP_NAME%"
set "NGINX_SERVICE_NAME=nginx"


:: === ADMINISTRATIVE CHECK ===
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo [ERROR] Administrative privileges are required.
    echo Attempting to re-launch as Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)


:MENU
cls
echo.
echo ======================= %APP_NAME% Manager [Windows] =======================
echo.
echo  -- System and Dependencies --
echo  0) Bootstrap Server (Python, Nginx, NSSM, Firewall)
echo  1) Setup SSL with Certbot (Fetch from Let's Encrypt)
echo  2) Setup SSL with Existing Certificates (Use local files)
echo.
echo  -- Nginx Web Server --
echo  3) Start/Enable Nginx Service
echo  4) Stop/Disable Nginx Service
echo  5) Reload Nginx Config
echo.
echo  -- Python Application --
echo  6) Install/Update App Service
echo  7) Start App Service
echo  8) Stop App Service
echo  9) Restart App Service
echo 10) View App Logs
echo 11) View App Status
echo 12) Uninstall App Service
echo.
echo ======================================================================
set /p choice="Enter number [0-12]: "
echo.

goto choice_%choice% 2>nul || goto invalid_choice

:: ============================================================================
:: SCRIPT LOGIC
:: ============================================================================

:choice_0
    echo [0] Bootstrapping System...

    :: --- Find Installers ---
    for %%F in ("%INSTALLERS_DIR%\python-*.exe") do set "PYTHON_EXE=%%~nxF"
    for %%F in ("%INSTALLERS_DIR%\nssm-*.zip") do set "NSSM_ZIP=%%~nxF"
    for %%F in ("%INSTALLERS_DIR%\nginx-*.zip") do set "NGINX_ZIP=%%~nxF"

    if not defined PYTHON_EXE (echo [ERROR] Python installer not found in %INSTALLERS_DIR% & goto end)
    if not defined NSSM_ZIP (echo [ERROR] NSSM zip not found in %INSTALLERS_DIR% & goto end)
    if not defined NGINX_ZIP (echo [ERROR] Nginx zip not found in %INSTALLERS_DIR% & goto end)
    
    echo Found: %PYTHON_EXE%, %NSSM_ZIP%, %NGINX_ZIP%

    :: --- Install Python ---
    echo.
    echo [TASK] Checking for a valid Python installation...
    python --version >nul 2>nul
    if %errorlevel% neq 0 (
        echo A valid Python installation was not found. The existing 'python' command may be a Microsoft Store alias.
        echo Installing Python from installer...
        "%INSTALLERS_DIR%\%PYTHON_EXE%" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
        echo.
        echo [!! ACTION REQUIRED !!]
        echo Python has been installed. You MUST CLOSE this terminal and RE-RUN the script.
        echo Please re-run Option 0 after restarting.
        echo.
        pause
        exit /b
    ) else (
        echo Python is already installed and configured correctly.
        python --version
    )

    :: --- Setup App Directory & Venv ---
    echo.
    echo [TASK] Creating Application Directories and Python venv...
    mkdir "%APP_DIR%" 2>nul
    mkdir "%LOG_DIR%" 2>nul
    if not exist "%VENV_PATH%\Scripts\python.exe" (
        echo Creating virtual environment...
        python -m venv "%VENV_PATH%"
        if errorlevel 1 (
            echo [ERROR] Failed to create virtual environment. Please check your Python installation.
            goto end
        ) else (
			echo Virtual environment created.
		)
    ) else (
        echo Virtual environment already exists.
    )
	
	echo Installing/updating Python packages from requirements.txt...
    if not exist "%APP_DIR%\requirements.txt" (
        echo [WARNING] requirements.txt not found in %APP_DIR%.
        echo Please create it and list your Python dependencies (e.g., waitress)
        echo Installing waitress as a default...
        "%VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip
        :: "%VENV_PATH%\Scripts\python.exe" -m pip install waitress
    ) else (
        echo Found requirements.txt. Installing dependencies...
        "%VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip
        :: "%VENV_PATH%\Scripts\python.exe" -m pip install -r "%APP_DIR%\requirements.txt"
    )

    :: --- Install NSSM ---
    echo.
    echo [TASK] Installing NSSM (Service Manager)...
    if not exist "%NSSM_EXE%" (
        echo Extracting NSSM...
        mkdir "%NSSM_DIR%" 2>nul
        powershell -Command "Expand-Archive -Path '%INSTALLERS_DIR%\%NSSM_ZIP%' -DestinationPath '%TEMP%\nssm_extract' -Force"
        for /f "delims=" %%i in ('dir /b /s "%TEMP%\nssm_extract\*nssm.exe"') do (
            copy "%%i" "%NSSM_EXE%" >nul
            goto found_nssm
        )
        :found_nssm
        rmdir /s /q "%TEMP%\nssm_extract"
        echo NSSM installed to %NSSM_DIR%.
		echo Adding NSSM to the system PATH. A terminal restart may be required for this to take full effect.
		setx PATH "%PATH%;%NSSM_DIR%" /M
    ) else (
        echo NSSM already found at %NSSM_EXE%.
    )

    :: --- Install Nginx ---
    echo.
    echo [TASK] Installing Nginx...
    if not exist "%NGINX_DIR%\nginx.exe" (
        echo Extracting Nginx...
        powershell -Command "Expand-Archive -Path '%INSTALLERS_DIR%\%NGINX_ZIP%' -DestinationPath '%TEMP%\nginx_extract' -Force"
        for /f "delims=" %%i in ('dir /b "%TEMP%\nginx_extract\nginx-*"') do (
            move "%TEMP%\nginx_extract\%%i" "%NGINX_DIR%" >nul
        )
        rmdir /s /q "%TEMP%\nginx_extract"
        echo Nginx installed to %NGINX_DIR%.
    ) else (
        echo Nginx already found at %NGINX_DIR%.
    )

    :: --- Install Certbot using pip (NEW OFFICIAL METHOD) ---
    echo.
    echo [TASK] Installing Certbot via pip...
    where certbot >nul 2>&1
    if %errorlevel% neq 0 (
        echo Certbot not found. Installing with pip into the system Python environment...
        python -m pip install --upgrade pip
        python -m pip install certbot certbot-nginx
        echo.
        echo [!! ACTION REQUIRED !!]
        echo Certbot has been installed. You may need to RESTART this terminal
        echo for the PATH changes to take effect before using Option 1.
        echo.
    ) else (
        echo Certbot is already installed.
    )

    :: --- Configure Nginx ---
    echo.
    echo [TASK] Configuring Nginx...
    mkdir "%NGINX_DIR%\servers" 2>nul
    mkdir "%NGINX_DIR%\logs" 2>nul
    set "NGINX_DIR_FWD=!NGINX_DIR:\=/!"
    (
        echo # Main Nginx Configuration - Generated by App Manager
        echo worker_processes  auto;
        echo pid           !NGINX_DIR_FWD!/logs/nginx.pid;
        echo error_log     !NGINX_DIR_FWD!/logs/error.log;
        echo events { worker_connections  1024; }
        echo http {
        echo     include       !NGINX_DIR_FWD!/conf/mime.types;
        echo     access_log    !NGINX_DIR_FWD!/logs/access.log;
        echo     default_type  application/octet-stream;
        echo     sendfile        on;
        echo     keepalive_timeout  65;
        echo     include       !NGINX_DIR_FWD!/servers/*.conf;
        echo }
    ) > "%NGINX_DIR%\conf\nginx.conf"
    (
        echo # HTTP server that proxies to the Python app
        echo server {
        echo     listen 80;
        echo     server_name %DOMAIN%;
        echo     location / {
        echo         proxy_pass http://127.0.0.1:%PORT%;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto \$scheme;
        echo     }
        echo }
    ) > "%NGINX_DIR%\servers\%APP_NAME%.conf"
    
    :: --- Install Nginx Service ---
    echo.
    echo [TASK] Installing Nginx as a Windows Service...
    "%NSSM_EXE%" status %NGINX_SERVICE_NAME% >nul 2>&1
    if %errorlevel% neq 0 (
        "%NSSM_EXE%" install %NGINX_SERVICE_NAME% "%NGINX_DIR%\nginx.exe"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppDirectory "%NGINX_DIR%"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppParameters "-g \"daemon off;\""
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% DisplayName "App Manager Nginx Web Server"
        echo Nginx service installed.
    ) else (
        echo Nginx service already installed.
    )

    :: --- Configure Firewall ---
    echo.
    echo [TASK] Configuring Windows Firewall...
    netsh advfirewall firewall show rule name="Nginx HTTP/HTTPS" >nul
    if %errorlevel% neq 0 (
        echo Creating firewall rule "Nginx HTTP/HTTPS"...
        netsh advfirewall firewall add rule name="Nginx HTTP/HTTPS" dir=in action=allow protocol=TCP localport=80,443
    ) else (
        echo Firewall rule "Nginx HTTP/HTTPS" already exists.
    )

    echo.
    echo [SUCCESS] Bootstrap complete.
    goto end
	
:choice_1
    echo [1] Setup SSL with Certbot...
    where certbot >nul 2>&1
    if %errorlevel% neq 0 (
        echo.
        echo [ERROR] Certbot not found.
        echo Please run Option 0 to install it automatically.
        goto end
    )
    echo [INFO] Certbot found.
    echo.
    echo Stopping Nginx to free up port 80 for validation...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME%
    timeout /t 5 >nul
    
    echo Running Certbot...
    certbot certonly --standalone -d %DOMAIN% --non-interactive --agree-tos -m %EMAIL% --config-dir "%CERTBOT_DIR%" --work-dir "%CERTBOT_DIR%\work" --logs-dir "%CERTBOT_DIR%\logs"
    if %errorlevel% neq 0 (
        echo [ERROR] Certbot failed. Please check the logs above.
        "%NSSM_EXE%" start %NGINX_SERVICE_NAME%
        goto end
    )
    
    echo SSL certificate obtained successfully.
    echo.
    echo Updating Nginx configuration for HTTPS...
    
    set "CERTBOT_DIR_FWD=!CERTBOT_DIR:\=/!"

    (
        echo # HTTP to HTTPS redirect
        echo server {
        echo     listen 80;
        echo     server_name %DOMAIN%;
        echo     return 301 https://\$host\$request_uri;
        echo }
        echo.
        echo # HTTPS server
        echo server {
        echo     listen 443 ssl http2;
        echo     server_name %DOMAIN%;
        echo.
        echo     # SSL Certificate paths are dynamic
        echo     ssl_certificate      !CERTBOT_DIR_FWD!/live/%DOMAIN%/fullchain.pem;
        echo     ssl_certificate_key  !CERTBOT_DIR_FWD!/live/%DOMAIN%/privkey.pem;
        echo.
        echo     # Recommended SSL settings from certbot
        echo     include !CERTBOT_DIR_FWD!/options-ssl-nginx.conf;
        echo     ssl_dhparam !CERTBOT_DIR_FWD!/ssl-dhparams.pem;
        echo.
        echo     location / {
        echo         proxy_pass http://127.0.0.1:%PORT%;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto https;
        echo     }
        echo }
    ) > "%NGINX_DIR%\servers\%APP_NAME%.conf"
    
    echo Restarting Nginx to apply new SSL config...
    :: Test config and then restart service, the most robust method
    "%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%/" -t
    if %errorlevel% neq 0 (
        echo [ERROR] Nginx config test failed. Please check manually.
        goto end
    )
    "%NSSM_EXE%" restart %NGINX_SERVICE_NAME%
    echo.
    echo [SUCCESS] SSL setup complete.
    goto end

:choice_2
    echo [2] Setting up Nginx SSL with existing certificates...

    echo Checking for certificate at: %EXISTING_CERT_PATH%
    echo Checking for key at: %EXISTING_KEY_PATH%

    if not exist "%EXISTING_CERT_PATH%" (
        echo.
        echo [ERROR] Certificate file not found at the specified path.
        echo Please check the "EXISTING_CERT_PATH" variable at the top of the script.
        goto end
    )
    if not exist "%EXISTING_KEY_PATH%" (
        echo.
        echo [ERROR] Private key file not found at the specified path.
        echo Please check the "EXISTING_KEY_PATH" variable at the top of the script.
        goto end
    )
    
    echo Files found. Updating Nginx configuration for HTTPS...
    
    :: Convert paths to use forward slashes for the Nginx config
    set "CERT_PATH_FWD=!EXISTING_CERT_PATH:\=/!"
    set "KEY_PATH_FWD=!EXISTING_KEY_PATH:\=/!"

    (
        echo # HTTP to HTTPS redirect
        echo server {
        echo     listen 80;
        echo     server_name %DOMAIN%;
        echo     return 301 https://\$host\$request_uri;
        echo }
        echo.
        echo # HTTPS server using existing certificates
        echo server {
        echo     listen 443 ssl http2;
        echo     server_name %DOMAIN%;
        echo.
        echo     # SSL Certificate paths are dynamic from script config
        echo     ssl_certificate      !CERT_PATH_FWD!;
        echo     ssl_certificate_key  !KEY_PATH_FWD!;
        echo.
        echo     # NOTE: Add custom ssl_ciphers, ssl_protocols, etc. here if needed
        echo.
        echo     location / {
        echo         proxy_pass http://127.0.0.1:%PORT%;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto https;
        echo     }
        echo }
    ) > "%NGINX_DIR%\servers\%APP_NAME%.conf"
    
    echo Restarting Nginx to apply new SSL config...
    "%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%/" -t
    if %errorlevel% neq 0 (
        echo [ERROR] Nginx config test failed. Please check manually.
        goto end
    )
    "%NSSM_EXE%" restart %NGINX_SERVICE_NAME%
    echo.
    echo [SUCCESS] SSL setup complete using existing certificates.
    goto end
	
:choice_3
    echo [3] Starting Nginx service...
    "%NSSM_EXE%" start %NGINX_SERVICE_NAME%
    goto end

:choice_4
    echo [4] Stopping Nginx service...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME%
    goto end

:choice_5
    echo [5] Reloading Nginx by Restarting the Service...
    echo Testing configuration before restart...
    :: We still test the config file to prevent starting the service with a bad config.
    "%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%/" -t

    if %errorlevel% equ 0 (
        echo Nginx config test successful. Restarting the Nginx service to apply changes...
        :: The correct way to reload a service is to restart it using the service manager.
        "%NSSM_EXE%" restart %NGINX_SERVICE_NAME%
        echo Nginx service has been restarted.
    ) else (
        echo.
        echo [ERROR] Nginx config test failed. ABORTING restart to prevent downtime.
        echo Please fix the configuration files in %NGINX_DIR%\conf or %NGINX_DIR%\servers.
    )
    goto end

:choice_6
    echo [6] Installing/Updating %APP_NAME% service...
    "%NSSM_EXE%" install "%APP_SERVICE_NAME%" "%VENV_PATH%\Scripts\python.exe" "-m waitress --call --host=127.0.0.1 --port=%PORT% %MODULE%"
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" AppDirectory "%APP_DIR%"
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" DisplayName "App Manager %APP_NAME% Application"
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" AppStdout "%LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" AppStderr "%LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" AppRotateFiles 1
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" AppRotateBytes 10485760
    "%NSSM_EXE%" set "%APP_SERVICE_NAME%" Start SERVICE_AUTO_START
    echo [SUCCESS] %APP_NAME% service has been installed/updated.
    echo To apply changes, restart the service (option 8).
    goto end

:choice_7
    echo [7] Starting %APP_NAME% service...
    "%NSSM_EXE%" start %APP_SERVICE_NAME%
    goto end

:choice_8
    echo [8] Stopping %APP_NAME% service...
    "%NSSM_EXE%" stop %APP_SERVICE_NAME%
    goto end

:choice_9
    echo [9] Restarting %APP_NAME% service...
    "%NSSM_EXE%" restart %APP_SERVICE_NAME%
    goto end

:choice_10
    echo [10] Viewing app logs (Press CTRL+C to stop)...
    if not exist "%LOG_DIR%\app.log" (
        echo Log file does not exist yet. Start the app to generate it.
    ) else (
        powershell Get-Content "%LOG_DIR%\app.log" -Wait -Tail 10
    )
    goto end

:choice_11
    echo [11] Checking %APP_NAME% service status...
    "%NSSM_EXE%" status %APP_SERVICE_NAME%
    goto end

:choice_12
    echo [12] Uninstalling %APP_NAME% service...
    "%NSSM_EXE%" stop %APP_SERVICE_NAME% >nul 2>&1
    "%NSSM_EXE%" remove %APP_SERVICE_NAME% confirm
    goto end

:invalid_choice
    echo [ERROR] Invalid choice.
    goto end

:end
echo.
pause
goto MENU