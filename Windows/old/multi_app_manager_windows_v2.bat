@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: App Manager for Windows - V2 (Robust & Context-Aware)
:: ============================================================================
:: This script manages the deployment and lifecycle of multiple web applications
:: on a single Windows server using Nginx, NSSM, and Certbot.
::
:: PREREQUISITES:
:: 1. Run this script as an Administrator. It will self-elevate.
:: 2. Create an "installers" folder in the same directory as this script.
:: 3. Place Python, Nginx (zip), and NSSM (zip) in the "installers" folder.
:: 4. Your application source code and a 'requirements.txt' should be ready.
::
:: NEW IN V2:
:: - Consolidated app management into a single "Manage Application" menu.
:: - The script now detects if an app is deployed and shows contextual
::   options (e.g., Deploy vs. Update/Uninstall).
:: - Streamlined main menu for better user experience.
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
::   - ROOT:      App runs on the main domain (e.g., yourdomain.com)
::   - SUBDOMAIN: App runs on a subdomain (e.g., app1.yourdomain.com)
::   - SUBPATH:   App runs on a path (e.g., yourdomain.com/app1)
::
:: CONFIGURATION:
:: - _APP_FOLDER:    Base directory for the app. 'source', 'venv', 'logs' will
::                   be created inside this folder.
:: - _PYTHON_MODULE: The Python module and callable, e.g., 'main:app' where
::                   'main.py' is inside the 'source' folder.
:: ============================================================================

set "APPS=MyWebApp,ApiServer"

:: --- App 1: MyWebApp (deployed to a root domain) ---
set "MyWebApp_DEPLOY_TYPE=ROOT"
set "MyWebApp_DOMAIN=%ROOT_DOMAIN%"
set "MyWebApp_PORT=8001"
set "MyWebApp_APP_FOLDER=%BASE_APPS_DIR%\MyWebApp"
set "MyWebApp_PYTHON_MODULE=source:create_app"

:: --- App 2: ApiServer (deployed to a subpath of the first app's domain) ---
set "ApiServer_DEPLOY_TYPE=SUBPATH"
set "ApiServer_DOMAIN=%ROOT_DOMAIN%"  :: The HOST domain
set "ApiServer_SUBPATH=/cs"              :: The unique path for this app
set "ApiServer_PORT=8003"
set "ApiServer_APP_FOLDER=%BASE_APPS_DIR%\ApiServer"
set "ApiServer_PYTHON_MODULE=source:create_app"

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
echo =================== Multi-App Manager V2 [Windows] ===================
echo.
echo  -- Initial Setup --
echo  0) Bootstrap Server (Install Python, Nginx, NSSM, Certbot)
echo.
echo  -- Core Actions --
echo  1) Manage an Application (Deploy, Update, Start, Stop, Uninstall)
echo.
echo  -- System-Wide Services --
echo  2) Manage Nginx Service (Start, Stop, Reload)
echo  3) Manage SSL Certificates (Renew All)
echo.
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
    call :ManageApplicationFlow
    goto end

:choice_2
    call :ManageNginxMenu
    goto end

:choice_3
    call :ManageSslMenu
    goto end


:: ============================================================================
:: FUNCTIONS / SUBROUTINES
:: ============================================================================

:: NEW: This is the main controller for all application management.
:ManageApplicationFlow
    call :SelectApp "manage"
    if not defined SELECTED_APP (
        echo Selection cancelled.
        goto :eof
    )
    call :LoadAppConfig %SELECTED_APP%

    :: Check the status of the app to decide which menu to show
    call :CheckAppStatus
    if "!APP_IS_DEPLOYED!"=="1" (
        call :DeployedAppMenu
    ) else (
        call :NotDeployedAppMenu
    )
    goto :eof

:: NEW: Helper function to check if the app's service exists.
:CheckAppStatus
    set "APP_IS_DEPLOYED=0"
    "%NSSM_EXE%" status "%CURRENT_APP_SERVICE_NAME%" >nul 2>&1
    if %errorlevel% equ 0 (
        set "APP_IS_DEPLOYED=1"
        echo [INFO] Application '%APP_NAME%' is already deployed.
    ) else (
        echo [INFO] Application '%APP_NAME%' is not yet deployed.
    )
    goto :eof

:: NEW: Menu shown for an application that is already deployed.
:DeployedAppMenu
    :deployed_menu_loop
    cls
    echo ============ Manage Deployed Application: %APP_NAME% =============
    echo.
    echo   Domain: %CURRENT_DOMAIN%
    echo   Port:   %CURRENT_PORT%
    if defined CURRENT_SUBPATH echo   Path:   %CURRENT_SUBPATH%
    echo   Service Name: %CURRENT_APP_SERVICE_NAME%
    echo.
    echo   -- Service Control --
    echo   1) Start Service
    echo   2) Stop Service
    echo   3) Restart Service
    echo   4) View Service Status
    echo   5) View App Logs (tail -f)
    echo.
    echo   -- Lifecycle Management --
    echo   6) Re-run Deployment (Update files and packages)
    echo   7) Uninstall Application
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
    if "%app_choice%"=="6" (call :DeployApp & pause & goto :eof)
    if "%app_choice%"=="7" (call :UninstallApp & pause & goto :eof)
    if "%app_choice%"=="0" (goto :eof)
    goto deployed_menu_loop

:: NEW: Menu shown for an application that has not been deployed yet.
:NotDeployedAppMenu
    :not_deployed_loop
    cls
    echo ======== Manage Application: %APP_NAME% (Not Yet Deployed) ========
    echo.
    echo   Domain: %CURRENT_DOMAIN%
    echo   Port:   %CURRENT_PORT%
    if defined CURRENT_SUBPATH echo   Path:   %CURRENT_SUBPATH%
    echo.
    echo   This application service has not been created yet.
    echo.
    echo   1) Deploy Application
    echo.
    echo   0) Back to Main Menu
    echo.
    set /p app_choice="Enter choice: "

    if "%app_choice%"=="1" (call :DeployApp & pause & goto :eof)
    if "%app_choice%"=="0" (goto :eof)
    goto not_deployed_loop

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
        set "menu_line=!i!) %%a"
        echo  !menu_line!
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
    set "CURRENT_APP_FOLDER=!%APP_NAME%_APP_FOLDER!"
    set "CURRENT_PYTHON_MODULE=!%APP_NAME%_PYTHON_MODULE!"

    :: Handle optional subpath
    set "CURRENT_SUBPATH="
    if defined %APP_NAME%_SUBPATH set "CURRENT_SUBPATH=!%APP_NAME%_SUBPATH!"

    :: Derive standard paths and names from the base app folder
    set "CURRENT_SOURCE_DIR=%CURRENT_APP_FOLDER%\source"
    set "CURRENT_VENV_PATH=%CURRENT_APP_FOLDER%\venv"
    set "CURRENT_LOG_DIR=%CURRENT_APP_FOLDER%\logs"
    set "CURRENT_APP_SERVICE_NAME=%APP_NAME%_App_Service"

    :: Nginx config file is named after the DOMAIN, not the APP_NAME, for easier grouping.
    set "NGINX_CONF_FILENAME=%CURRENT_DOMAIN%.conf"
    set "CURRENT_NGINX_CONF_FILE=%NGINX_DIR%\servers\%NGINX_CONF_FILENAME%"
    goto :eof


:DeployApp
    echo.
    echo [ACTION] Deploying / Updating application: %APP_NAME% on domain %CURRENT_DOMAIN%
    echo.

    :: --- SSL Configuration Choice ---
    set "SSL_CHOICE="
    echo How do you want to configure this deployment?
    echo  1. HTTP only (no SSL)
    echo  2. HTTPS (use existing certificate)
    echo  3. HTTPS (generate new certificate with Certbot)
    set /p SSL_CHOICE="Enter choice [1]: "
    if not defined SSL_CHOICE set "SSL_CHOICE=1"

    if "%SSL_CHOICE%"=="3" (
        call :ObtainCertificate "%CURRENT_DOMAIN%"
        if errorlevel 1 (
            echo.
            echo [ERROR] Failed to obtain certificate. Aborting deployment.
            goto :eof
        )
    )

    :: --- Setup App Directory & Venv ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Creating Application Directories and Python venv...
    mkdir "%CURRENT_APP_FOLDER%" 2>nul
    mkdir "%CURRENT_SOURCE_DIR%" 2>nul
    mkdir "%CURRENT_LOG_DIR%" 2>nul

    if not exist "%CURRENT_VENV_PATH%\Scripts\python.exe" (
        echo Creating virtual environment...
        python -m venv "%CURRENT_VENV_PATH%"
        if errorlevel 1 (echo [ERROR] Failed to create venv. & goto :eof)
    ) else (
        echo Virtual environment already exists.
    )

    :: --- Install Dependencies ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Installing/updating Python packages...
    echo.
    if not exist "%CURRENT_APP_FOLDER%\requirements.txt" (
        echo [WARNING] 'requirements.txt' not found. Installing 'waitress' as a default server.
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip waitress
    ) else (
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install -r "%CURRENT_APP_FOLDER%\requirements.txt"
    )

    :: --- Generate Nginx Configuration ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Generating Nginx configuration...
    call :GenerateNginxConfigFileForDomain "%CURRENT_DOMAIN%" "%SSL_CHOICE%"

    :: --- Install App Service ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Installing/Updating %APP_NAME% as a Windows Service...
    echo.
    "%NSSM_EXE%" install "%CURRENT_APP_SERVICE_NAME%" "%CURRENT_VENV_PATH%\Scripts\waitress-serve.exe" --call --host=127.0.0.1 --port=%CURRENT_PORT% %CURRENT_PYTHON_MODULE%
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppDirectory "%CURRENT_APP_FOLDER%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" DisplayName "[App Manager] %APP_NAME%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppStdout "%CURRENT_LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppStderr "%CURRENT_LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppRotateFiles 1
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppRotateBytes 10485760
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" Start SERVICE_AUTO_START

    echo.
    echo ======================================================================
    echo.
    echo [SUCCESS] Deployment/update complete for %APP_NAME%.
    echo You may need to:
    echo  - Reload the main Nginx service to apply the new site config.
    echo  - Start the %APP_NAME% service from the 'Manage Application' menu.
    goto :eof


:GenerateNginxConfigFileForDomain
    set "TARGET_DOMAIN=%~1"
    set "SSL_MODE=%~2"
    set "CONF_FILE=%NGINX_DIR%\servers\%TARGET_DOMAIN%.conf"
    echo Generating Nginx config for domain %TARGET_DOMAIN% in SSL mode %SSL_MODE%

    set "SSL_CERT_PATH=!CERTBOT_DIR:\=/!/live/%TARGET_DOMAIN%/fullchain.pem"
    set "SSL_KEY_PATH=!CERTBOT_DIR:\=/!/live/%TARGET_DOMAIN%/privkey.pem"

    :: Find the primary app (ROOT or SUBDOMAIN) for this domain
    set "PRIMARY_APP_NAME="
    for %%a in (%APPS%) do (
        if "!%%a_DOMAIN!"=="%TARGET_DOMAIN%" (
            if "!%%a_DEPLOY_TYPE!"=="ROOT" set "PRIMARY_APP_NAME=%%a"
            if "!%%a_DEPLOY_TYPE!"=="SUBDOMAIN" set "PRIMARY_APP_NAME=%%a"
        )
    )

    if not defined PRIMARY_APP_NAME (
        echo [ERROR] Could not find a primary ROOT or SUBDOMAIN app for domain '%TARGET_DOMAIN%'. Cannot generate config.
        goto :eof
    )

    set "PRIMARY_PORT=!%PRIMARY_APP_NAME%_PORT!"
    echo Primary app for this domain is %PRIMARY_APP_NAME% on port %PRIMARY_PORT%

    :: Determine if HTTPS should be configured
    set "USE_HTTPS=0"
    if "%SSL_MODE%"=="2" (set "USE_HTTPS=1")
    if "%SSL_MODE%"=="3" (set "USE_HTTPS=1")

    :: Start writing the config file from scratch
    (
        if %USE_HTTPS% equ 1 (
            echo # HTTP to HTTPS redirect
            echo server {
            echo     listen 80;
            echo     server_name %TARGET_DOMAIN%;
            echo     return 301 https://\$host\$request_uri;
            echo }
            echo.
        )
        echo # Main Application Server Block for %TARGET_DOMAIN%
        echo server {
        if %USE_HTTPS% equ 1 (
            echo     listen 443 ssl http2;
            echo     server_name %TARGET_DOMAIN%;
            echo     ssl_certificate      !SSL_CERT_PATH!;
            echo     ssl_certificate_key  !SSL_KEY_PATH!;
            echo     include !CERTBOT_DIR:\=/!/options-ssl-nginx.conf;
            echo     ssl_dhparam !CERTBOT_DIR:\=/!/ssl-dhparams.pem;
        ) else (
            echo     listen 80;
            echo     server_name %TARGET_DOMAIN%;
        )
        echo.
        echo     # Location for the primary app: %PRIMARY_APP_NAME%
        echo     location / {
        echo         proxy_pass http://127.0.0.1:%PRIMARY_PORT%;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto \$scheme;
        echo     }

        :: Now, find and add all SUBPATH apps for this domain
        for %%a in (%APPS%) do (
            if "!%%a_DOMAIN!"=="%TARGET_DOMAIN%" (
                if "!%%a_DEPLOY_TYPE!"=="SUBPATH" (
                    echo.
                    echo     # Location block for Subpath App: %%a
                    echo     # IMPORTANT: The trailing slash on proxy_pass is critical!
                    echo     location !%%a_SUBPATH!/ {
                    echo         proxy_pass http://127.0.0.1:!%%a_PORT!/;
                    echo         proxy_set_header Host \$host;
                    echo         proxy_set_header X-Real-IP \$remote_addr;
                    echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                    echo         proxy_set_header X-Forwarded-Proto \$scheme;
                    echo     }
                )
            )
        )

        echo }
    ) > "%CONF_FILE%"

    echo [SUCCESS] Nginx config file created/updated at %CONF_FILE%
    goto :eof


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
    echo ====================== Manage SSL Certificates =======================
    echo.
    echo This will attempt to renew ALL existing certificates.
    echo Certbot will automatically skip certificates that are not yet due for renewal.
    echo This is the recommended way to keep certificates up-to-date.
    echo.
    set /p confirm="Proceed with renewal? (y/n): "
    if /i not "%confirm%"=="y" goto :eof

    echo.
    echo ======================================================================
    echo.
    echo [INFO] Stopping Nginx to allow Certbot to run...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME%
    timeout /t 5 >nul

    echo.
    echo ======================================================================
    echo.
    echo Running Certbot renewal...
    certbot renew --config-dir "%CERTBOT_DIR%" --work-dir "%CERTBOT_DIR%\work" --logs-dir "%CERTBOT_DIR%\logs"

    echo.
    echo ======================================================================
    echo.
    echo [INFO] Restarting Nginx...
    "%NSSM_EXE%" start %NGINX_SERVICE_NAME%
    goto :eof

:ObtainCertificate
    set "DOMAIN_FOR_CERT=%~1"
    echo.
    echo [ACTION] Obtaining certificate for %DOMAIN_FOR_CERT%
    echo This will stop Nginx temporarily to free up port 80.
    echo.
    set /p confirm="Proceed? (y/n): "
    if /i not "%confirm%"=="y" (
        echo Certificate generation cancelled.
        exit /b 1
    )

    echo.
    echo ======================================================================
    echo.
    echo [INFO] Stopping Nginx...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME% >nul 2>&1
    timeout /t 5 >nul

    echo.
    echo ======================================================================
    echo.
    echo [TASK] Running Certbot...
    certbot certonly --standalone -d %DOMAIN_FOR_CERT% --non-interactive --agree-tos -m %CERTBOT_EMAIL% --config-dir "%CERTBOT_DIR%" --work-dir "%CERTBOT_DIR%\work" --logs-dir "%CERTBOT_DIR%\logs"
    if %errorlevel% neq 0 (
        echo.
        echo [ERROR] Certbot failed. Check logs in %CERTBOT_DIR%\logs.
        echo [INFO] Restarting Nginx...
        "%NSSM_EXE%" start %NGINX_SERVICE_NAME% >nul 2>&1
        exit /b 1
    )

    echo.
    echo [SUCCESS] Certificate obtained for %DOMAIN_FOR_CERT%.
    :: Nginx is left stopped, the calling function will handle restart
    goto :eof

:UninstallApp
    echo.
    echo [ACTION] Uninstalling application: %APP_NAME%
    echo.
    echo This will stop and remove the Windows service.
    echo If this is the PRIMARY app for a domain, the Nginx config will be DELETED.
    echo If this is a SUBPATH app, the Nginx config will be REGENERATED without it.
    echo It will NOT delete the application source code, venv, or logs.
    echo.
    set /p confirm="Are you sure you want to uninstall %APP_NAME%? (y/n): "
    if /i not "%confirm%"=="y" (
        echo Uninstall cancelled.
        goto :eof
    )

    echo.
    echo [TASK] Stopping and removing service %CURRENT_APP_SERVICE_NAME%...
    "%NSSM_EXE%" stop %CURRENT_APP_SERVICE_NAME% >nul 2>&1
    "%NSSM_EXE%" remove %CURRENT_APP_SERVICE_NAME% confirm

    :: If this is a primary app, delete its config. If a subpath, regenerate the config.
    if "%CURRENT_DEPLOY_TYPE%"=="ROOT" or "%CURRENT_DEPLOY_TYPE%"=="SUBDOMAIN" (
        echo [INFO] Removing Nginx config file %CURRENT_NGINX_CONF_FILE%...
        if exist "%CURRENT_NGINX_CONF_FILE%" (
            del "%CURRENT_NGINX_CONF_FILE%"
        )
    ) else if "%CURRENT_DEPLOY_TYPE%"=="SUBPATH" (
        echo [INFO] This is a subpath app. Removing it from the app list temporarily to regenerate the config...
        set "temp_apps=%APPS:,%APP_NAME%=%"
        set "temp_apps=%temp_apps:%APP_NAME%,=%"
        set APPS=%temp_apps%
        call :GenerateNginxConfigFileForDomain "%CURRENT_DOMAIN%" "1"
        echo [INFO] Nginx config for %CURRENT_DOMAIN% regenerated without %APP_NAME%.
    )

    echo.
    echo [SUCCESS] %APP_NAME% has been uninstalled.
    echo Please reload the Nginx service (Option 2) to apply changes.
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
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Checking Python...
    python --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo Installing Python...
        "%PYTHON_EXE%" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
        echo [!! ACTION REQUIRED !!] Python installed. CLOSE this terminal and RE-RUN the script.
        pause & exit /b
    ) else ( echo Python is already installed. )

    :: --- Install NSSM ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Installing NSSM...
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
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Installing Nginx...
    if not exist "%NGINX_DIR%\nginx.exe" (
        echo Extracting Nginx...
        powershell -Command "Expand-Archive -Path '%NGINX_ZIP%' -DestinationPath '%TEMP%\nginx_extract' -Force"
        for /f "delims=" %%i in ('dir /b "%TEMP%\nginx_extract\nginx-*"') do move "%TEMP%\nginx_extract\%%i" "%NGINX_DIR%" >nul
        rmdir /s /q "%TEMP%\nginx_extract"
        echo Nginx installed to %NGINX_DIR%.
    ) else ( echo Nginx already found. )

    :: --- Install Certbot ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Installing Certbot via pip...
    where certbot >nul 2>&1
    if %errorlevel% neq 0 (
        echo Certbot not found. Installing with pip...
        python -m pip install --upgrade pip
        python -m pip install certbot
        echo Certbot installed. A terminal restart may be needed.
    ) else ( echo Certbot is already installed. )

    :: --- Configure Global Nginx Settings ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Configuring Nginx...
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

    :: --- Create Default Nginx Welcome Page Config ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Creating default Nginx welcome page config...
    (
        echo # Default server block to catch requests to the root domain or IP
        echo # This will be overridden if you deploy an app to the ROOT_DOMAIN.
        echo server {
        echo     listen 80 default_server;
        echo     listen [::]:80 default_server;
        echo     server_name %ROOT_DOMAIN% _;
        echo     root !NGINX_DIR_FWD!/html;
        echo     index index.html index.htm;
        echo.
        echo     location / {
        echo         try_files \$uri \$uri/ =404;
        echo     }
        echo }
    ) > "%NGINX_DIR%\servers\00-default.conf"

    :: --- Install Nginx Service ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Installing Nginx as a Windows Service...
    "%NSSM_EXE%" status %NGINX_SERVICE_NAME% >nul 2>nul
    if %errorlevel% neq 0 (
        "%NSSM_EXE%" install %NGINX_SERVICE_NAME% "%NGINX_DIR%\nginx.exe"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppDirectory "%NGINX_DIR%"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppParameters "-g \"daemon off;\""
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% DisplayName "[App Manager] Nginx"
        echo Nginx service installed.
    ) else ( echo Nginx service already installed. )

    :: --- Configure Firewall ---
    echo.
    echo ======================================================================
    echo.
    echo [TASK] Configuring Windows Firewall...
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