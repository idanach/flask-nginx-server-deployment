@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: App Manager for Windows - V3 (Intuitive & Self-Healing)
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
:: NEW IN V3:
:: - Reworked application configuration into a single, easy-to-manage block.
::   Simply add or remove `call :RegisterApp` lines to manage your apps.
:: - Smart management of Nginx's default config. Deploying a ROOT app
::   now automatically disables the default Nginx welcome page.
:: - Uninstalling the last ROOT app automatically restores the welcome page.
:: - Clarified distinction between ROOT/SUBDOMAIN and SUBPATH deployments.
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
:: === APPLICATION CONFIGURATION (REWORKED) ===
:: ============================================================================
:: This is the central place to define all your applications.
:: To add a new app, simply add a new `call :RegisterApp` line.
:: To remove an app, comment out or delete its line.

call :ConfigureApplications
goto :AfterAppConfig

:ConfigureApplications
    set "APP_COUNT=0"

    :: Usage: call :RegisterApp "AppName" "DeployType" "Domain" "Port" "PythonModule" "Subpath"
    :: - AppName:      A unique, descriptive name for your app.
    :: - DeployType:   ROOT, SUBDOMAIN, or SUBPATH.
    ::   - ROOT:      The main app for your root domain (e.g., test.com).
    ::                This will replace the default Nginx page.
    ::   - SUBDOMAIN: The main app for a subdomain (e.g., api.test.com).
    ::   - SUBPATH:   An app that runs under a path (e.g., test.com/cs).
    ::                It MUST share a domain with a ROOT or SUBDOMAIN app.
    :: - Domain:       The full domain name for the app.
    :: - Port:         A unique local port for the app (e.g., 8001, 8002).
    :: - PythonModule: The module:callable for waitress (e.g., 'main:app').
    :: - Subpath:      (Required for SUBPATH type, otherwise leave empty "") The path (e.g., /cs).

    call :RegisterApp "testapp1"    "ROOT"      "%ROOT_DOMAIN%"         "8001"  "source:create_app" ""
    call :RegisterApp "testapp2"    "SUBPATH"   "%ROOT_DOMAIN%"         "8003"  "source:create_app" "/cs"
    call :RegisterApp "testapp3"    "SUBDOMAIN" "test.%ROOT_DOMAIN%"    "8003"  "source:create_app" ""

    goto :eof


:: REWORKED: This function now populates our structured app "array"
:RegisterApp
    set /a APP_COUNT+=1
    set "app_%APP_COUNT%_NAME=%~1"
    set "app_%APP_COUNT%_TYPE=%~2"
    set "app_%APP_COUNT%_DOMAIN=%~3"
    set "app_%APP_COUNT%_PORT=%~4"
    set "app_%APP_COUNT%_PYTHON_MODULE=%~5"
    set "app_%APP_COUNT%_SUBPATH=%~6"

    :: Derive standard paths from the app name
    set "app_%APP_COUNT%_APP_FOLDER=%BASE_APPS_DIR%\%~1"
goto :eof

:AfterAppConfig
:: This is a list of ALL app names, generated automatically from the config above.
set "APPS="
for /l %%i in (1, 1, %APP_COUNT%) do (
    set "APPS=!APPS!,!app_%%i_NAME!"
)
if defined APPS set "APPS=%APPS:~1%"


:: === ADMINISTRATIVE CHECK ===
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo [ERROR] Administrative privileges are required.
    echo [TASK] Attempting to re-launch as Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)


:MENU
cls
echo.
echo =================== Multi-App Manager V3 [Windows] ===================
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

:ManageApplicationFlow
    call :SelectApp "manage"
    if not defined SELECTED_APP_INDEX (
        echo [INFO] Selection cancelled.
        goto :eof
    )
    call :LoadAppConfig %SELECTED_APP_INDEX%

    call :CheckAppStatus
    if "!APP_IS_DEPLOYED!"=="1" (
        call :DeployedAppMenu
    ) else (
        call :NotDeployedAppMenu
    )
    goto :eof


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


:: REWORKED: SelectApp now uses the structured app array
:SelectApp
    set "ACTION_TYPE=%~1"
    set "SELECTED_APP_INDEX="
    cls
    echo.
    echo Please select an application to %ACTION_TYPE%:
    echo.
    for /l %%i in (1, 1, %APP_COUNT%) do (
        REM This is the corrected line:
        call echo   %%i^) !app_%%i_NAME! (!app_%%i_TYPE! on !app_%%i_DOMAIN!^)
    )
    echo.
    set /p app_choice="Enter number: "
    if %app_choice% gtr 0 if %app_choice% leq %APP_COUNT% (
        set "SELECTED_APP_INDEX=%app_choice%"
    ) else (
        echo [ERROR] Invalid selection.
    )
    goto :eof

:: REWORKED: LoadAppConfig now uses the selected index to load variables
:LoadAppConfig
    set "APP_INDEX=%1"
    set "APP_NAME=!app_%APP_INDEX%_NAME!"
    echo [INFO] Loading configuration for %APP_NAME%...

    :: Dynamically set CURRENT_* variables from the selected app's config
    set "CURRENT_DEPLOY_TYPE=!app_%APP_INDEX%_TYPE!"
    set "CURRENT_DOMAIN=!app_%APP_INDEX%_DOMAIN!"
    set "CURRENT_PORT=!app_%APP_INDEX%_PORT!"
    set "CURRENT_PYTHON_MODULE=!app_%APP_INDEX%_PYTHON_MODULE!"
    set "CURRENT_SUBPATH=!app_%APP_INDEX%_SUBPATH!"
    set "CURRENT_APP_FOLDER=!app_%APP_INDEX%_APP_FOLDER!"

    :: Derive standard paths and names from the base app folder
    set "CURRENT_SOURCE_DIR=%CURRENT_APP_FOLDER%\source"
    set "CURRENT_VENV_PATH=%CURRENT_APP_FOLDER%\venv"
    set "CURRENT_LOG_DIR=%CURRENT_APP_FOLDER%\logs"
    set "CURRENT_APP_SERVICE_NAME=%APP_NAME%_App_Service"

    :: Nginx config file is named after the DOMAIN
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
    echo [TASK] Creating Application Directories and Python venv...
    mkdir "%CURRENT_APP_FOLDER%" 2>nul
    mkdir "%CURRENT_SOURCE_DIR%" 2>nul
    mkdir "%CURRENT_LOG_DIR%" 2>nul

    if not exist "%CURRENT_VENV_PATH%\Scripts\python.exe" (
        echo [INFO] Creating virtual environment...
        python -m venv "%CURRENT_VENV_PATH%"
        if errorlevel 1 (echo [ERROR] Failed to create venv. & goto :eof)
    ) else ( echo [INFO] Virtual environment already exists. )

    :: --- Install Dependencies ---
    echo.
    echo [TASK] Installing/updating Python packages...
    if not exist "%CURRENT_APP_FOLDER%\requirements.txt" (
        echo [WARNING] 'requirements.txt' not found. Installing 'waitress' as a default server.
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip waitress
    ) else (
        "%CURRENT_VEN V_PATH%\Scripts\python.exe" -m pip install --upgrade pip
        "%CURRENT_VENV_PATH%\Scripts\python.exe" -m pip install -r "%CURRENT_APP_FOLDER%\requirements.txt"
    )

    :: --- Generate Nginx Configuration ---
    echo.
    echo [TASK] Generating Nginx configuration...
    call :GenerateNginxConfigFileForDomain "%CURRENT_DOMAIN%" "%SSL_CHOICE%"

    :: NEW: If this is a ROOT app, disable the default Nginx page
    if "%CURRENT_DEPLOY_TYPE%"=="ROOT" (
        call :DisableDefaultNginxConfig
    )

    :: --- Install App Service ---
    echo.
    echo [TASK] Installing/Updating %APP_NAME% as a Windows Service...
    "%NSSM_EXE%" install "%CURRENT_APP_SERVICE_NAME%" "%CURRENT_VENV_PATH%\Scripts\waitress-serve.exe" --call --host=127.0.0.1 --port=%CURRENT_PORT% %CURRENT_PYTHON_MODULE%
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppDirectory "%CURRENT_APP_FOLDER%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" DisplayName "[App Manager] %APP_NAME%"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppStdout "%CURRENT_LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppStderr "%CURRENT_LOG_DIR%\app.log"
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppRotateFiles 1
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" AppRotateBytes 10485760
    "%NSSM_EXE%" set "%CURRENT_APP_SERVICE_NAME%" Start SERVICE_AUTO_START

    echo.
    echo [SUCCESS] Deployment/update complete for %APP_NAME%.
    echo You may need to:
    echo  - Reload the main Nginx service to apply the new site config.
    echo  - Start the %APP_NAME% service from the 'Manage Application' menu.
    goto :eof


:: REWORKED: Now loops through the structured app array
:GenerateNginxConfigFileForDomain
    set "TARGET_DOMAIN=%~1"
    set "SSL_MODE=%~2"
    set "CONF_FILE=%NGINX_DIR%\servers\%TARGET_DOMAIN%.conf"
    echo [INFO] Generating Nginx config for domain %TARGET_DOMAIN% in SSL mode %SSL_MODE%

    set "SSL_CERT_PATH=!CERTBOT_DIR:\=/!/live/%TARGET_DOMAIN%/fullchain.pem"
    set "SSL_KEY_PATH=!CERTBOT_DIR:\=/!/live/%TARGET_DOMAIN%/privkey.pem"

    :: Find the primary app (ROOT or SUBDOMAIN) for this domain
    set "PRIMARY_APP_PORT="
    set "PRIMARY_APP_NAME="
    for /l %%i in (1, 1, %APP_COUNT%) do (
        if "!app_%%i_DOMAIN!"=="%TARGET_DOMAIN%" (
            if "!app_%%i_TYPE!"=="ROOT" (
                set "PRIMARY_APP_PORT=!app_%%i_PORT!"
                set "PRIMARY_APP_NAME=!app_%%i_NAME!"
            )
            if "!app_%%i_TYPE!"=="SUBDOMAIN" (
                set "PRIMARY_APP_PORT=!app_%%i_PORT!"
                set "PRIMARY_APP_NAME=!app_%%i_NAME!"
            )
        )
    )

    if not defined PRIMARY_APP_PORT (
        echo [ERROR] Could not find a primary ROOT or SUBDOMAIN app for domain '%TARGET_DOMAIN%'. Cannot generate config.
        goto :eof
    )

    echo [INFO] Primary app for this domain is %PRIMARY_APP_NAME% on port %PRIMARY_APP_PORT%

    set "USE_HTTPS=0"
    if "%SSL_MODE%"=="2" (set "USE_HTTPS=1")
    if "%SSL_MODE%"=="3" (set "USE_HTTPS=1")

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
        echo         proxy_pass http://127.0.0.1:%PRIMARY_APP_PORT%;
        echo         proxy_set_header Host \$host;
        echo         proxy_set_header X-Real-IP \$remote_addr;
        echo         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        echo         proxy_set_header X-Forwarded-Proto \$scheme;
        echo     }

        :: Now, find and add all SUBPATH apps for this domain
        for /l %%i in (1, 1, %APP_COUNT%) do (
            if "!app_%%i_DOMAIN!"=="%TARGET_DOMAIN%" (
                if "!app_%%i_TYPE!"=="SUBPATH" (
                    echo.
                    echo     # Location block for Subpath App: !app_%%i_NAME!
                    echo     # IMPORTANT: The trailing slash on proxy_pass is critical!
                    echo     location !app_%%i_SUBPATH!/ {
                    echo         proxy_pass http://127.0.0.1:!app_%%i_PORT!/;
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


:UninstallApp
    echo.
    echo [ACTION] Uninstalling application: %APP_NAME%
    echo.
    echo This will stop and remove the Windows service.
    echo It will NOT delete the application source code, venv, or logs.
    echo.
    set /p confirm="Are you sure you want to uninstall %APP_NAME%? (y/n): "
    if /i not "%confirm%"=="y" ( echo Uninstall cancelled. & goto :eof )

    echo.
    echo [TASK] Stopping and removing service %CURRENT_APP_SERVICE_NAME%...
    "%NSSM_EXE%" stop %CURRENT_APP_SERVICE_NAME% >nul 2>&1
    "%NSSM_EXE%" remove %CURRENT_APP_SERVICE_NAME% confirm

    :: REWORKED: More robust Nginx config handling on uninstall
    echo [TASK] Updating Nginx configuration...
    if "%CURRENT_DEPLOY_TYPE%"=="ROOT" or "%CURRENT_DEPLOY_TYPE%"=="SUBDOMAIN" (
        echo [INFO] This is a primary app. Removing its Nginx config file...
        if exist "%CURRENT_NGINX_CONF_FILE%" del "%CURRENT_NGINX_CONF_FILE%"

        :: NEW: After removing a ROOT app, check if we need to restore the default page
        if "%CURRENT_DEPLOY_TYPE%"=="ROOT" (
            call :RestoreDefaultNginxConfigIfNeeded "%APP_NAME%"
        )
    ) else if "%CURRENT_DEPLOY_TYPE%"=="SUBPATH" (
        echo [INFO] This is a subpath app. Regenerating the parent domain's config without it...
        call :GenerateNginxConfigFileForDomain "%CURRENT_DOMAIN%" "1"
    )

    echo.
    echo [SUCCESS] %APP_NAME% has been uninstalled.
    echo [INFO] Please reload the Nginx service to apply changes.
    goto :eof

:: NEW: Function to disable the default Nginx welcome page
:DisableDefaultNginxConfig
    set "DEFAULT_CONF=%NGINX_DIR%\servers\00-default.conf"
    if exist "%DEFAULT_CONF%" (
        echo [INFO] Disabling default Nginx welcome page for ROOT app deployment...
        ren "%DEFAULT_CONF%" "00-default.conf.disabled"
    )
    goto :eof

:: NEW: Function to restore the default page if no other ROOT apps exist
:RestoreDefaultNginxConfigIfNeeded
    set "UNINSTALLED_APP_NAME=%~1"
    set "ANOTHER_ROOT_APP_EXISTS=0"

    :: Check if any *other* ROOT app is still configured
    for /l %%i in (1, 1, %APP_COUNT%) do (
        if "!app_%%i_TYPE!"=="ROOT" (
            if /i not "!app_%%i_NAME!"=="%UNINSTALLED_APP_NAME%" (
                set "ANOTHER_ROOT_APP_EXISTS=1"
            )
        )
    )

    if %ANOTHER_ROOT_APP_EXISTS% equ 1 (
        echo [INFO] Another ROOT application still exists. Default page will remain disabled.
    ) else (
        echo [INFO] No other ROOT applications found. Re-enabling default Nginx welcome page...
        set "DISABLED_CONF=%NGINX_DIR%\servers\00-default.conf.disabled"
        if exist "%DISABLED_CONF%" (
            ren "%DISABLED_CONF%" "00-default.conf"
        )
    )
    goto :eof


:: ============================================================================
:: === BOOTSTRAP AND SYSTEM FUNCTIONS (Largely unchanged) =====================
:: ============================================================================
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
        echo [INFO] Testing config before restarting...
        "%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%/" -t
        if !errorlevel! equ 0 (
            echo [INFO] Config OK. Restarting Nginx...
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
    echo.
    set /p confirm="Proceed with renewal? (y/n): "
    if /i not "%confirm%"=="y" goto :eof

    echo [INFO] Stopping Nginx to allow Certbot to run...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME%
    timeout /t 5 >nul
    echo [INFO] Running Certbot renewal...
    certbot renew --config-dir "%CERTBOT_DIR%" --work-dir "%CERTBOT_DIR%\work" --logs-dir "%CERTBOT_DIR%\logs"
    echo [INFO] Restarting Nginx...
    "%NSSM_EXE%" start %NGINX_SERVICE_NAME%
    goto :eof

:ObtainCertificate
    set "DOMAIN_FOR_CERT=%~1"
    echo [ACTION] Obtaining certificate for %DOMAIN_FOR_CERT%
    echo [INFO] This will stop Nginx temporarily to free up port 80.
    set /p confirm="Proceed? (y/n): "
    if /i not "%confirm%"=="y" ( echo [INFO] Certificate generation cancelled. & exit /b 1 )

    echo [INFO] Stopping Nginx...
    "%NSSM_EXE%" stop %NGINX_SERVICE_NAME% >nul 2>&1
    timeout /t 5 >nul
    echo [TASK] Running Certbot...
    certbot certonly --standalone -d %DOMAIN_FOR_CERT% --non-interactive --agree-tos -m %CERTBOT_EMAIL% --config-dir "%CERTBOT_DIR%" --work-dir "%CERTBOT_DIR%\work" --logs-dir "%CERTBOT_DIR%\logs"
    if %errorlevel% neq 0 (
        echo [ERROR] Certbot failed. Check logs in %CERTBOT_DIR%\logs.
        echo [INFO] Restarting Nginx...
        "%NSSM_EXE%" start %NGINX_SERVICE_NAME% >nul 2>&1
        exit /b 1
    )
    echo [SUCCESS] Certificate obtained for %DOMAIN_FOR_CERT%.
    goto :eof

:BootstrapServer
    echo [0] Bootstrapping System (Shared Components)...
    for %%F in ("%INSTALLERS_DIR%\python-*.exe") do set "PYTHON_EXE=%%~F"
    for %%F in ("%INSTALLERS_DIR%\nssm-*.zip") do set "NSSM_ZIP=%%~F"
    for %%F in ("%INSTALLERS_DIR%\nginx-*.zip") do set "NGINX_ZIP=%%~F"
    if not defined PYTHON_EXE (echo [ERROR] Python installer not found. & goto :eof)
    if not defined NSSM_ZIP (echo [ERROR] NSSM zip not found. & goto :eof)
    if not defined NGINX_ZIP (echo [ERROR] Nginx zip not found. & goto :eof)

    echo.
    echo [TASK] Checking Python...
    python --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo [INFO] Installing Python...
        "%PYTHON_EXE%" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
        echo [!! ACTION REQUIRED !!] Python installed. CLOSE this terminal and RE-RUN the script.
        pause & exit /b
    ) else ( echo [INFO] Python is already installed. )

    echo.
    echo [TASK] Installing Certbot via pip...
    where certbot >nul 2>&1
    if %errorlevel% neq 0 (
        python -m pip install --upgrade pip
        python -m pip install certbot
    ) else ( echo [INFO] Certbot is already installed. )

    echo.
    echo [TASK] Installing NSSM...
    if not exist "%NSSM_EXE%" (
        echo [INFO] Extracting NSSM...
        mkdir "%NSSM_DIR%" 2>nul
        powershell -Command "Expand-Archive -Path '%NSSM_ZIP%' -DestinationPath '%TEMP%\nssm_extract' -Force"
        for /f "delims=" %%i in ('dir /b /s "%TEMP%\nssm_extract\*nssm.exe"') do copy "%%i" "%NSSM_EXE%" >nul
        rmdir /s /q "%TEMP%\nssm_extract"
        setx PATH "%PATH%;%NSSM_DIR%" /M
    ) else ( echo [INFO] NSSM already found. )

    echo.
    echo [TASK] Installing Nginx...
    if not exist "%NGINX_DIR%\nginx.exe" (
        echo [INFO] Extracting Nginx...
        powershell -Command "Expand-Archive -Path '%NGINX_ZIP%' -DestinationPath '%TEMP%\nginx_extract' -Force"
        for /f "delims=" %%i in ('dir /b "%TEMP%\nginx_extract\nginx-*"') do move "%TEMP%\nginx_extract\%%i" "%NGINX_DIR%" >nul
        rmdir /s /q "%TEMP%\nginx_extract"
    ) else ( echo [INFO] Nginx already found. )

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
        echo.
        echo     # Increase bucket size to allow for multiple/long server names
        echo     server_names_hash_bucket_size 64;
        echo.
        echo     # Include all server block configurations
        echo     include       !NGINX_DIR_FWD!/servers/*.conf;
        echo }
    ) > "%NGINX_DIR%\conf\nginx.conf"

    echo [TASK] Creating default Nginx welcome page config...
    set "DEFAULT_CONF_FILE=%NGINX_DIR%\servers\00-default.conf"
    if not exist "%DEFAULT_CONF_FILE%" if not exist "%DEFAULT_CONF_FILE%.disabled" (
        (
        echo # Default server block to catch requests to the root domain or IP
        echo server {
        echo     listen 80 default_server;
        echo     listen [::]:80 default_server;
        echo     server_name _;
        echo     root !NGINX_DIR_FWD!/html;
        echo     location / { try_files \$uri \$uri/ =404; }
        echo }
        ) > "%DEFAULT_CONF_FILE%"
    )

    echo [TASK] Installing Nginx as a Windows Service...
    "%NSSM_EXE%" status %NGINX_SERVICE_NAME% >nul 2>nul
    if %errorlevel% neq 0 (
        "%NSSM_EXE%" install %NGINX_SERVICE_NAME% "%NGINX_DIR%\nginx.exe"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppDirectory "%NGINX_DIR%"
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% AppParameters "-g \"daemon off;\""
        "%NSSM_EXE%" set %NGINX_SERVICE_NAME% DisplayName "[App Manager] Nginx"
    ) else ( echo [INFO] Nginx service already installed. )

    echo.
    echo [TASK] Configuring Windows Firewall...
    netsh advfirewall firewall show rule name="Nginx HTTP/HTTPS" >nul
    if %errorlevel% neq 0 (
        netsh advfirewall firewall add rule name="Nginx HTTP/HTTPS" dir=in action=allow protocol=TCP localport=80,443
    ) else ( echo [INFO] Firewall rule already exists. )

    echo.
    echo [SUCCESS] Bootstrap complete.
    goto :eof

:end
echo.
pause
goto MENU