@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: App Manager for Windows - V1 (Multi-App Support)
:: ============================================================================
:: This script manages the deployment and lifecycle of multiple web applications
:: on a single Windows server using Nginx, NSSM, and Certbot.
::
:: PREREQUISITES:
:: 1. Run this script as an Administrator. It will self-elevate.
:: 2. Create an "installers" folder in the same directory as this script.
:: 3. Place Python, Nginx (zip), and NSSM (zip) in the "installers" folder.
:: 4. Your application source code and a 'requirements.txt' should be ready.
:: ============================================================================

:: ============================================================================
:: === GLOBAL CONFIGURATION ===
:: ============================================================================
set "ROOT_DOMAIN=yourdomain.com"

set "ACTIVE_DRIVE=C:"
set "BASE_APPS_DIR=%ACTIVE_DRIVE%\www"
set "INSTALLERS_DIR=%~dp0installers"

:: --- Shared Tool Paths ---
set "NGINX_DIR=%ACTIVE_DRIVE%\nginx"
set "NSSM_DIR=%ACTIVE_DRIVE%\nssm"
set "CERTBOT_DIR=%ACTIVE_DRIVE%\Certbot"
set "NSSM_EXE=%NSSM_DIR%\nssm.exe"
set "NGINX_SERVICE_NAME=nginx"

:: --- SSL Defaults ---
set "CERTBOT_EMAIL=admin@%ROOT_DOMAIN%"


:: ============================================================================
:: === APPLICATION DEFINITIONS ===
:: ============================================================================
:: Define your applications here. Add new app names to the APPS list.
:: For each app, create a corresponding configuration block.
::
:: DEPLOY_TYPE can be:
::   - ROOT:      App runs on the main domain (e.g., mydomain.com)
::   - SUBDOMAIN: App runs on a subdomain (e.g., app1.mydomain.com)
::   - SUBPATH:   App runs on a path (e.g., mydomain.com/app1)
::
:: IMPORTANT: For SUBPATH, you must also define the _SUBPATH variable.
:: ============================================================================

set "APPS=MyWebApp,ApiServer,ProjectPhoenix"

:: --- App 1: MyWebApp (deployed to a subdomain) ---
set "MyWebApp_DEPLOY_TYPE=SUBDOMAIN"
set "MyWebApp_DOMAIN=webapp.%ROOT_DOMAIN%"
set "MyWebApp_PORT=8001"
set "MyWebApp_SOURCE_DIR=%BASE_APPS_DIR%\my-web-app\source"
set "MyWebApp_MODULE=main:app"

:: --- App 2: ApiServer (deployed to a different subdomain) ---
set "ApiServer_DEPLOY_TYPE=SUBDOMAIN"
set "ApiServer_DOMAIN=api.%ROOT_DOMAIN%"
set "ApiServer_PORT=8002"
set "ApiServer_SOURCE_DIR=%BASE_APPS_DIR%\api-server\source"
set "ApiServer_MODULE=api:create_app"

:: --- App 3: ProjectPhoenix (deployed to a subpath of the first app's domain) ---
set "ProjectPhoenix_DEPLOY_TYPE=SUBPATH"
set "ProjectPhoenix_DOMAIN=webapp.%ROOT_DOMAIN%"  :: NOTE: This is the HOST domain
set "ProjectPhoenix_SUBPATH=/phoenix"              :: The unique path for this app
set "ProjectPhoenix_PORT=8003"
set "ProjectPhoenix_SOURCE_DIR=%BASE_APPS_DIR%\project-phoenix\source"
set "ProjectPhoenix_MODULE=server:app"


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
echo ===================== Multi-App Manager V1 [Windows] ====================
echo.
echo  -- Initial Setup --
echo  0) Bootstrap Server (Install Python, Nginx, NSSM, Certbot)
echo.
echo  -- Application Management --
echo  1) Deploy / Update an Application
echo  2) Manage an Existing Application (Start, Stop, Logs, etc.)
echo  3) Uninstall an Application
echo.
echo  -- Global Services --
echo  4) Manage Nginx Service (Start, Stop, Reload)
echo  5) Manage SSL Certificates with Certbot
echo.
echo ======================================================================
set /p choice="Enter your choice: "
echo.

goto choice_%choice% 2>nul || (echo [ERROR] Invalid choice. & pause & goto MENU)

:: ============================================================================
:: SCRIPT LOGIC
:: ============================================================================

:choice_0
    call :BootstrapServer
    goto end

:choice_1
    call :SelectApp "deploy"
    if defined SELECTED_APP (
        call :LoadAppConfig %SELECTED_APP%
        call :DeployApp
    )
    goto end

:choice_2
    call :SelectApp "manage"
    if defined SELECTED_APP (
        call :LoadAppConfig %SELECTED_APP%
        call :AppManagementMenu
    )
    goto end

:choice_3
    call :SelectApp "uninstall"
    if defined SELECTED_APP (
        call :LoadAppConfig %SELECTED_APP%
        call :UninstallApp
    )
    goto end

:choice_4
    call :ManageNginxMenu
    goto end

:choice_5
    call :ManageSslMenu
    goto end

:: ============================================================================
:: FUNCTIONS / SUBROUTINES
:: ============================================================================

:SelectApp
    set "ACTION_TYPE=%~1"
    set "SELECTED_APP="
    cls
    echo.
    echo Please select an application to %ACTION_TYPE%:
    echo.
    set i=0
    for %%a in (%APPS%) do (
        set /a i+=1
        echo  !i!) %%a
        set "app_!i!=%%a"
    )
    echo.
    set /p app_choice="Enter number: "
    if defined app_%app_choice% (
        set "SELECTED_APP=!app_%app_choice%!"
    ) else (
        echo [ERROR] Invalid selection.
    )
    goto :eof


:LoadAppConfig
    set "APP_NAME=%1"
    echo [INFO] Loading configuration for %APP_NAME%...

    :: Dynamically set CURRENT_* variables from the selected app's config
    set "CURRENT_DEPLOY_TYPE=!%APP_NAME%_DEPLOY_TYPE!"
    set "CURRENT_DOMAIN=!%APP_NAME%_DOMAIN!"
    set "CURRENT_PORT=!%APP_NAME%_PORT!"
    set "CURRENT_SOURCE_DIR=!%APP_NAME%_SOURCE_DIR!"
    set "CURRENT_MODULE=!%APP_NAME%_MODULE!"

    :: Handle optional subpath
    set "CURRENT_SUBPATH="
    if defined %APP_NAME%_SUBPATH set "CURRENT_SUBPATH=!%APP_NAME%_SUBPATH!"

    :: Derive standard paths and names
    set "CURRENT_APP_DIR=%BASE_APPS_DIR%\%APP_NAME%"
    set "CURRENT_VENV_PATH=%CURRENT_APP_DIR%\venv"
    set "CURRENT_LOG_DIR=%CURRENT_APP_DIR%\logs"
    set "CURRENT_APP_SERVICE_NAME=%APP_NAME%_App_Service"
    set "CURRENT_NGINX_CONF_FILE=%NGINX_DIR%\servers\%APP_NAME%.conf"
    goto :eof


:DeployApp
    echo.
    echo [ACTION] Deploying / Updating application: %APP_NAME%
    echo.

    :: --- Setup App Directory & Venv ---
    echo [TASK] Creating Application Directories and Python venv...
    mkdir "%CURRENT_APP_DIR%" 2>nul
    mkdir "%CURRENT_LOG_DIR%" 2>nul
    mkdir "%CURRENT_SOURCE_DIR%" 2>nul

    if not exist "%CURRENT_VENV_PATH%\Scripts\python.exe" (
        echo Creating virtual environment in %CURRENT_VENV_PATH%...
        python -m venv "%CURRENT_VENV_PATH%"
        if errorlevel 1 (echo [ERROR] Failed to create venv. & goto :eof)
    ) else (
        echo Virtual environment already exists.
    )

    :: --- Install Dependencies ---
    echo [TASK] Installing/updating Python packages...
    if not exist "%CURRENT_SOURCE_DIR%\requirements.txt" (
        echo [WARNING] 'requirements.txt' not found in %CURRENT_SOURCE_DIR%.
        echo Please create it. Installing 'waitress' as a default production server.
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip waitress
    ) else (
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install -r "%CURRENT_SOURCE_DIR%\requirements.txt"
    )

    :: --- Generate Nginx Configuration ---
    echo [TASK] Generating Nginx configuration...
    call :GenerateNginxConfig

    :: --- Install App Service ---
    echo [TASK] Installing %APP_NAME% as a Windows Service...
    "%NSSM_EXE%" status %CURRENT_APP_SERVICE_NAME% >nul 2>&1
    if %errorlevel% neq 0 (
        echo Installing new service: %CURRENT_APP_SERVICE_NAME%
    ) else (
        echo Updating existing service: %CURRENT_APP_SERVICE_NAME%
    )
    "%NSSM_EXE%" install "%CURRENT_APP_SERVICE_NAME%" "%CURRENT_VENV_PATH%\Scripts\python.exe" "-m waitress --call --host=127.0.0.1 --port=%CURRENT_PORT% %CURRENT_MODULE%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppDirectory "%CURRENT_SOURCE_DIR%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" DisplayName "[App Manager] %APP_NAME%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppStdout "%CURRENT_LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppStderr "%CURRENT_LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppRotateFiles 1
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppRotateBytes 10485760
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" Start SERVICE_AUTO_START

    echo.
    echo [SUCCESS] Deployment/update complete for %APP_NAME%.
    echo You may need to:
    echo  - Run 'Manage SSL' to get a certificate for %CURRENT_DOMAIN%.
    echo  - Reload the main Nginx service (Option 4) to apply the new site config.
    echo  - Start the %APP_NAME% service from the 'Manage Application' menu.
    goto :eof


:GenerateNginxConfig
    echo Generating config for DEPLOY_TYPE: %CURRENT_DEPLOY_TYPE%

    set "SSL_CERT_PATH=!CERTBOT_DIR:\=/!/live/%CURRENT_DOMAIN%/fullchain.pem"
    set "SSL_KEY_PATH=!CERTBOT_DIR:\=/!/live/%CURRENT_DOMAIN%/privkey.pem"
    set "NGINX_DIR_FWD=!NGINX_DIR:\=/!"

    :: Check if an SSL certificate already exists for this domain
    if exist "%CERTBOT_DIR%\live\%CURRENT_DOMAIN%\fullchain.pem" (
        set "SSL_CONFIG_TYPE=HTTPS"
    ) else (
        set "SSL_CONFIG_TYPE=HTTP_ONLY"
    )
    echo SSL status for %CURRENT_DOMAIN%: %SSL_CONFIG_TYPE%

    :: SUBPATH deployment requires a different server block structure
    if "%CURRENT_DEPLOY_TYPE%"=="SUBPATH" (
        call :GenerateNginxSubpathConfig
    ) else (
        call :GenerateNginxDomainConfig
    )
    goto :eof

:GenerateNginxDomainConfig
    (
        if "!SSL_CONFIG_TYPE!"=="HTTPS" (
            echo # HTTP to HTTPS redirect
            echo server {
            echo     listen 80;
            echo     server_name %CURRENT_DOMAIN%;
            echo     return 301 https://\$host\$request_uri;
            echo }
            echo.
        )
        echo # Main Application Server Block
        echo server {
        if "!SSL_CONFIG_TYPE!"=="HTTPS" (
            echo     listen 443 ssl http2;
            echo     ssl_certificate      !SSL_CERT_PATH!;
            echo     ssl_certificate_key  !SSL_KEY_PATH!;
            echo     include !CERTBOT_DIR:\=/!/options-ssl-nginx.conf;
            echo     ssl_dhparam !CERTBOT_DIR:\=/!/ssl-dhparams.pem;
        ) else (
            echo     listen 80;
        )
        echo     server_name %CURRENT_DOMAIN%;
        echo.
        echo     location / {
        echo         proxy_pass http://127.0.0.1:%CURRENT_PORT%;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto \$scheme;
        echo     }
        echo }
    ) > "%CURRENT_NGINX_CONF_FILE%"
    echo Nginx config file for %APP_NAME% created at %CURRENT_NGINX_CONF_FILE%
    goto :eof

:GenerateNginxSubpathConfig
    :: For subpath, we assume the config file for the root/subdomain already exists
    :: and we just append the new location block to it.
    if not exist "%CURRENT_NGINX_CONF_FILE%" (
        echo [ERROR] For SUBPATH deployment, the config for the host domain '%CURRENT_DOMAIN%' must exist first.
        echo Please deploy the ROOT or SUBDOMAIN app for '%CURRENT_DOMAIN%' before deploying this subpath app.
        goto :eof
    )
    echo [INFO] Appending location block to existing config: %CURRENT_NGINX_CONF_FILE%
    (
        echo.
        echo     # Location block for Subpath App: %APP_NAME%
        echo     # IMPORTANT: The trailing slash on proxy_pass is critical!
        echo     location %CURRENT_SUBPATH%/ {
        echo         proxy_pass http://127.0.0.1:%CURRENT_PORT%/;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto \$scheme;
        echo     }
    ) >> "%CURRENT_NGINX_CONF_FILE%"
    :: We must remove the final closing brace '}' and re-add it at the end
    powershell -Command "(Get-Content -raw '%CURRENT_NGINX_CONF_FILE%') -replace '}\s*}$','' | Set-Content -NoNewline '%CURRENT_NGINX_CONF_FILE%.tmp'; echo. >> '%CURRENT_NGINX_CONF_FILE%.tmp'; Move-Item '%CURRENT_NGINX_CONF_FILE%.tmp' '%CURRENT_NGINX_CONF_FILE%' -Force"
    echo } >> "%CURRENT_NGINX_CONF_FILE%"

    echo Nginx config file for %APP_NAME% has been updated.
    goto :eof


:AppManagementMenu
    :app_menu_loop
    cls
    echo ============ Manage Application: %APP_NAME% =============
    echo.
    echo   Domain: %CURRENT_DOMAIN%
    echo   Port:   %CURRENT_PORT%
    echo   Path:   %CURRENT_SUBPATH%
    echo   Service Name: %CURRENT_APP_SERVICE_NAME%
    echo.
    echo   1) Start Service
    echo   2) Stop Service
    echo   3) Restart Service
    echo   4) View Service Status
    echo   5) View App Logs (tail -f)
    echo.
    echo   0) Back to Main Menu
    echo.
    set /p app_choice="Enter choice: "

    if "%app_choice%"=="1" ("%NSSM_EXE%" start %CURRENT_APP_SERVICE_NAME% & pause)
    if "%app_choice%"=="2" ("%NSSM_EXE%" stop %CURRENT_APP_SERVICE_NAME% & pause)
    if "%app_choice%"=="3" ("%NSSM_EXE%" restart %CURRENT_APP_SERVICE_NAME% & pause)
    if "%app_choice%"=="4" ("%NSSM_EXE%" status %CURRENT_APP_SERVICE_NAME% & pause)
    if "%app_choice%"=="5" (
        if not exist "%CURRENT_LOG_DIR%\app.log" (
            echo Log file does not exist yet.
        ) else (
            echo Tailing log file. Press CTRL+C to stop.
            powershell Get-Content "%CURRENT_LOG_DIR%\app.log" -Wait -Tail 20
        )
        pause
    )
    if "%app_choice%"=="0" (goto :eof)
    goto app_menu_loop

:ManageNginxMenu
    :nginx_menu_loop
    cls
    echo ============ Manage Nginx Service =============
    echo.
    echo   1) Start Nginx Service
    echo   2) Stop Nginx Service
    echo   3) Reload Nginx Config (Restart Service)
    echo   4) Test Nginx Configuration
    echo.
    echo   0) Back to Main Menu
    echo.
    set /p nginx_choice="Enter choice: "
    if "%nginx_choice%"=="1" ("%NSSM_EXE%" start %NGINX_SERVICE_NAME% & pause)
    if "%nginx_choice%"=="2" ("%NSSM_EXE%" stop %NGINX_SERVICE_NAME% & pause)
    if "%nginx_choice%"=="3" (
        echo Testing config before restarting...
        "%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%/" -t
        if !errorlevel! equ 0 (
            echo Config OK. Restarting Nginx...
            "%NSSM_EXE%" restart %NGINX_SERVICE_NAME%
        ) else (
            echo [ERROR] Nginx config test failed. Aborting restart.
        )
        pause
    )
    if "%nginx_choice%"=="4" ("%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%/" -t & pause)
    if "%nginx_choice%"=="0" (goto :eof)
    goto nginx_menu_loop


:ManageSslMenu
    cls
    echo ============== Manage SSL Certificates ==============
    echo.
    echo Which domain do you want to get/renew a certificate for?
    echo (This will stop Nginx temporarily for validation).
    echo.
    set i=0
    set "DOMAINS="
    :: Create a unique list of domains from app configs
    for %%a in (%APPS%) do (
        set "domain_to_add=!%%a_DOMAIN!"
        echo !DOMAINS! | find /i "!domain_to_add!" >nul
        if errorlevel 1 (
            set "DOMAINS=!DOMAINS! !domain_to_add!"
            set /a i+=1
            echo  !i!) !domain_to_add!
            set "domain_!i!=!domain_to_add!"
        )
    )
    echo.
    set /p domain_choice="Enter number: "
    if not defined domain_%domain_choice% (
        echo [ERROR] Invalid selection. & goto :eof
    )
    set "DOMAIN_FOR_CERT=!domain_%domain_choice%!"

    echo.
    echo [INFO] Proceeding with certificate generation for %DOMAIN_FOR_CERT%
    echo Stopping Nginx to free up port 80...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME%
    timeout /t 5 >nul

    echo Running Certbot...
    certbot certonly --standalone -d %DOMAIN_FOR_CERT% --non-interactive --agree-tos -m %CERTBOT_EMAIL% --config-dir "%CERTBOT_DIR%" --work-dir "%CERTBOT_DIR%\work" --logs-dir "%CERTBOT_DIR%\logs"
    if %errorlevel% neq 0 (
        echo [ERROR] Certbot failed. Check logs. Restarting Nginx...
        "%NSSM_EXE%" start %NGINX_SERVICE_NAME%
        goto :eof
    )

    echo [SUCCESS] Certificate obtained for %DOMAIN_FOR_CERT%.
    echo You must now re-deploy any applications using this domain to update their Nginx configs to use HTTPS.
    echo For example, run Option 1 and select an app using %DOMAIN_FOR_CERT%.
    echo.
    echo Restarting Nginx...
    "%NSSM_EXE%" start %NGINX_SERVICE_NAME%
    goto :eof


:UninstallApp
    echo.
    echo [ACTION] Uninstalling application: %APP_NAME%
    echo.
    echo This will stop and remove the Windows service and delete the Nginx config file.
    echo It will NOT delete the application source code or virtual environment.
    echo.
    set /p confirm="Are you sure you want to uninstall %APP_NAME%? (y/n): "
    if /i not "%confirm%"=="y" (
        echo Uninstall cancelled.
        goto :eof
    )

    echo Stopping and removing service %CURRENT_APP_SERVICE_NAME%...
    "%NSSM_EXE%" stop %CURRENT_APP_SERVICE_NAME% >nul 2>&1
    "%NSSM_EXE%" remove %CURRENT_APP_SERVICE_NAME% confirm

    echo Removing Nginx config file %CURRENT_NGINX_CONF_FILE%...
    if exist "%CURRENT_NGINX_CONF_FILE%" (
        del "%CURRENT_NGINX_CONF_FILE%"
    )

    echo.
    echo [SUCCESS] %APP_NAME% has been uninstalled.
    echo Please reload the Nginx service (Option 4) to apply changes.
    goto :eof

:BootstrapServer
    echo [0] Bootstrapping System (Shared Components)...

    :: --- Find Installers ---
    for %%F in ("%INSTALLERS_DIR%\python-*.exe") do set "PYTHON_EXE=%%~F"
    for %%F in ("%INSTALLERS_DIR%\nssm-*.zip") do set "NSSM_ZIP=%%~F"
    for %%F in ("%INSTALLERS_DIR%\nginx-*.zip") do set "NGINX_ZIP=%%~F"
    if not defined PYTHON_EXE (echo [ERROR] Python installer not found. & goto :eof)
    if not defined NSSM_ZIP (echo [ERROR] NSSM zip not found. & goto :eof)
    if not defined NGINX_ZIP (echo [ERROR] Nginx zip not found. & goto :eof)

    :: --- Install Python ---
    echo. & echo [TASK] Checking Python...
    python --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo Installing Python...
        "%PYTHON_EXE%" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
        echo [!! ACTION REQUIRED !!] Python installed. CLOSE this terminal and RE-RUN the script.
        pause & exit /b
    ) else ( echo Python is already installed. )

    :: --- Install NSSM ---
    echo. & echo [TASK] Installing NSSM...
    if not exist "%NSSM_EXE%" (
        echo Extracting NSSM...
        mkdir "%NSSM_DIR%" 2>nul
        powershell -Command "Expand-Archive -Path '%NSSM_ZIP%' -DestinationPath '%TEMP%\nssm_extract' -Force"
        for /f "delims=" %%i in ('dir /b /s "%TEMP%\nssm_extract\*nssm.exe"') do copy "%%i" "%NSSM_EXE%" >nul
        rmdir /s /q "%TEMP%\nssm_extract"
        echo NSSM installed to %NSSM_DIR%. Adding to PATH.
        setx PATH "%PATH%;%NSSM_DIR%" /M
        echo A terminal restart may be required for PATH changes to take effect.
    ) else ( echo NSSM already found. )

    :: --- Install Nginx ---
    echo. & echo [TASK] Installing Nginx...
    if not exist "%NGINX_DIR%\nginx.exe" (
        echo Extracting Nginx...
        powershell -Command "Expand-Archive -Path '%NGINX_ZIP%' -DestinationPath '%TEMP%\nginx_extract' -Force"
        for /f "delims=" %%i in ('dir /b "%TEMP%\nginx_extract\nginx-*"') do move "%TEMP%\nginx_extract\%%i" "%NGINX_DIR%" >nul
        rmdir /s /q "%TEMP%\nginx_extract"
        echo Nginx installed to %NGINX_DIR%.
    ) else ( echo Nginx already found. )

    :: --- Install Certbot ---
    echo. & echo [TASK] Installing Certbot via pip...
    where certbot >nul 2>&1
    if %errorlevel% neq 0 (
        echo Certbot not found. Installing with pip...
        python -m pip install --upgrade pip
        python -m pip install certbot certbot-nginx
        echo Certbot installed. A terminal restart may be needed.
    ) else ( echo Certbot is already installed. )

    :: --- Configure Global Nginx Settings ---
    echo. & echo [TASK] Configuring Nginx...
    mkdir "%NGINX_DIR%\servers" 2>nul
    mkdir "%NGINX_DIR%\logs" 2>nul
    set "NGINX_DIR_FWD=!NGINX_DIR:\=/!"
    (
        echo worker_processes  auto;
        echo pid           !NGINX_DIR_FWD!/logs/nginx.pid;
        echo error_log     !NGINX_DIR_FWD!/logs/error.log;
        echo events { worker_connections  1024; }
        echo http {
        echo     include       !NGINX_DIR_FWD!/conf/mime.types;
        echo     access_log    !NGINX_DIR_FWD!/logs/access.log;
        echo     sendfile        on;
        echo     keepalive_timeout  65;
        echo     # Include all application server configs
        echo     include       !NGINX_DIR_FWD!/servers/*.conf;
        echo }
    ) > "%NGINX_DIR%\conf\nginx.conf"

    :: --- Install Nginx Service ---
    echo. & echo [TASK] Installing Nginx as a Windows Service...
    "%NSSM_EXE%" status %NGINX_SERVICE_NAME% >nul 2>&1
    if %errorlevel% neq 0 (
        "%NSSM_EXE%" install %NGINX_SERVICE_NAME% "%NGINX_DIR%\nginx.exe"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppDirectory "%NGINX_DIR%"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppParameters "-g \"daemon off;\""
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% DisplayName "[App Manager] Nginx"
        echo Nginx service installed.
    ) else ( echo Nginx service already installed. )

    :: --- Configure Firewall ---
    echo. & echo [TASK] Configuring Windows Firewall...
    netsh advfirewall firewall show rule name="Nginx HTTP/HTTPS" >nul
    if %errorlevel% neq 0 (
        netsh advfirewall firewall add rule name="Nginx HTTP/HTTPS" dir=in action=allow protocol=TCP localport=80,443
        echo Firewall rule created.
    ) else ( echo Firewall rule already exists. )

    echo.
    echo [SUCCESS] Bootstrap complete.
    goto :eof

:end
echo.
pause
goto MENU