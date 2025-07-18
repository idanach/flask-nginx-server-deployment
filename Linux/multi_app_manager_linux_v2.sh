#!/bin/bash

# ============================================================================
# Multi-App Manager for Linux - V2 (Robust & Consistent)
# ============================================================================
# This script manages the deployment and lifecycle of multiple web applications
# on a single Linux (Debian/Ubuntu) server using Nginx, systemd, and Certbot.
#
# PREREQUISITES:
# 1. Run this script as a non-root user with sudo privileges (e.g., 'ubuntu').
# 2. Your application source code and a 'requirements.txt' should be ready.
#
# CHANGES IN V2:
# - [FIX] Removed `set -e`. The script now handles errors gracefully, especially
#         during Certbot operations, instead of exiting abruptly.
# - [FIX] The Nginx config generation now correctly distinguishes between a
#         primary app (ROOT/SUBDOMAIN/STATIC) and SUBPATH apps on the same domain,
#         preventing incorrect `location /` block generation.
# - [FIX] `RestoreDefaultNginxConfigIfNeeded` now correctly checks for STATIC apps
#         in addition to ROOT apps before re-enabling the default Nginx page.
# - [ENH] `SyncAndClean` function was rewritten to be more robust and reliable
#         using an associative array.
# - [QOL] Menus and prompts are now more consistent, providing better feedback
#         (e.g., showing service status directly in the management menu).
# - [QOL] Improved error messages and prompts for better clarity.
# ============================================================================

# ============================================================================
# === GLOBAL CONFIGURATION ===
# ============================================================================
ROOT_DOMAIN="yourdomain.com"
CERTBOT_EMAIL="admin@${ROOT_DOMAIN}"

# --- System Paths & User ---
# User that will own the app files and run the service.
# This user MUST have sudo privileges to run this script.
DEPLOY_USER="ubuntu"
BASE_APPS_DIR="/srv/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
SYSTEMD_DIR="/etc/systemd/system"
SSL_DHPARAMS_FILE="/etc/ssl/certs/dhparam.pem"
SSL_OPTIONS_FILE="/etc/letsencrypt/options-ssl-nginx.conf"

# ============================================================================
# === APPLICATION CONFIGURATION ===
# ============================================================================
# This is the central place to define all your applications.
# To add a new app, add a `RegisterApp` line. To remove one, comment it out.

# --- Initialize empty arrays for app properties ---
declare -a APP_NAMES APP_TYPES APP_DOMAINS APP_PORTS APP_MODULES APP_SUBPATHS

function RegisterApp() {
    # Usage: RegisterApp "AppName" "DeployType" "Domain" "Port" "PythonModule" "Subpath"
    # - DeployType: ROOT, SUBDOMAIN, SUBPATH, or STATIC.
    # - Port & PythonModule: Ignored for STATIC type (use "").
    # - Subpath: Required for SUBPATH type (e.g., /cs), otherwise use "".
    if [[ -z "$1" || -z "$2" || -z "$3" ]]; then
        echo "[CONFIG ERROR] AppName, DeployType, and Domain are required for '$1'." >&2
        exit 1
    fi
    APP_NAMES+=("$1")
    APP_TYPES+=("$2")
    APP_DOMAINS+=("$3")
    APP_PORTS+=("$4")
    APP_MODULES+=("$5")
    APP_SUBPATHS+=("$6")
}

function ConfigureApplications() {
    # --- A static landing page at the root domain ---
    RegisterApp "LandingPage" "STATIC"    "${ROOT_DOMAIN}"      ""      ""                  ""

    # --- A Python app on a subdomain ---
    RegisterApp "testapp2"    "SUBDOMAIN" "test.${ROOT_DOMAIN}" "8002"  "source:create_app()" ""

    # --- A Python app running under a subpath of the main domain ---
    RegisterApp "testapp2"    "SUBPATH"   "${ROOT_DOMAIN}"      "8003"  "source:create_app()" "/cs"
}

# --- Populate the application arrays ---
ConfigureApplications
APP_COUNT=${#APP_NAMES[@]}

# ============================================================================
# === SCRIPT LOGIC ===
# ============================================================================

# --- Helper for user confirmation ---
function press_enter_to_continue() {
    read -p "Press [Enter] to continue..."
}

# --- Administrative Check ---
if [[ $EUID -eq 0 ]]; then
   echo "[ERROR] This script should be run as a non-root user with sudo privileges, not as root."
   exit 1
fi
if ! sudo -v; then
    echo "[ERROR] Sudo privileges are required. Please check your user's permissions."
    exit 1
fi

function MainMenu() {
    while true; do
        clear
        echo "=================== Multi-App Manager V2 [Linux] ==================="
        echo
        echo " -- Initial Setup --"
        echo " 0) Bootstrap Server (Install Nginx, Python, Certbot, UFW)"
        echo
        echo " -- Core Actions --"
        echo " 1) Manage an Application (Deploy, Update, Start, Stop, Uninstall)"
        echo
        echo " -- System-Wide Services --"
        echo " 2) Manage Nginx Service (Start, Stop, Reload, Test)"
        echo " 3) Manage SSL Certificates (Renew, Generate Wildcard)"
        echo " 4) Sync and Clean Stale Nginx Configs"
        echo
        echo " q) Quit"
        echo "======================================================================"
        read -p "Enter your choice [0-4, q]: " choice
        echo

        case "$choice" in
            0) BootstrapServer; press_enter_to_continue ;;
            1) ManageApplicationFlow; press_enter_to_continue ;;
            2) ManageNginxMenu ;;
            3) ManageSslMenu ;;
            4) SyncAndClean; press_enter_to_continue ;;
            q) echo "Exiting."; exit 0 ;;
            *) echo "[ERROR] Invalid choice."; press_enter_to_continue ;;
        esac
    done
}

# ============================================================================
# --- MENU FUNCTIONS ---
# ============================================================================

function BootstrapServer() {
    echo "🧱 Updating system and installing essentials..."
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install -y nginx certbot python3-certbot-nginx python3-pip python3-venv ufw openssl openssh-server

    echo "🔧 Removing conflicting default Nginx config if it exists..."
    if [[ -L "/etc/nginx/sites-enabled/default" ]]; then
        echo "Found default Nginx symlink. Removing it."
        sudo rm "/etc/nginx/sites-enabled/default"
    fi

    echo "🔧 Creating base application directory..."
    sudo mkdir -p "$BASE_APPS_DIR"
    sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "$BASE_APPS_DIR"
    sudo chmod -R 775 "$BASE_APPS_DIR"

    echo "📄 Creating our script's default Nginx welcome page config..."
    if [[ ! -f "${NGINX_SITES_AVAILABLE}/00-default" ]]; then
        sudo tee "${NGINX_SITES_AVAILABLE}/00-default" > /dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.html index.nginx-debian.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        sudo ln -sf "${NGINX_SITES_AVAILABLE}/00-default" "${NGINX_SITES_ENABLED}/00-default"
    fi

    echo "🔐 Creating Certbot SSL helper configurations..."
    sudo mkdir -p "$(dirname "$SSL_OPTIONS_FILE")"
    if [[ ! -f "$SSL_OPTIONS_FILE" ]]; then
        sudo tee "$SSL_OPTIONS_FILE" > /dev/null <<EOF
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF
    fi

    if [[ ! -f "$SSL_DHPARAMS_FILE" ]]; then
        echo "🔐 Generating DH parameters for SSL (2048 bit). This may take a few minutes..."
        sudo openssl dhparam -out "$SSL_DHPARAMS_FILE" 2048
    else
        echo "✅ DH parameters file already exists."
    fi

    echo "🛡️ Configuring Firewall (UFW)..."
    sudo ufw allow 'Nginx Full'
    sudo ufw allow 'OpenSSH'
    sudo ufw --force enable

    echo "🚀 Starting and enabling Nginx..."
    sudo systemctl enable --now nginx

    echo "✅ Bootstrap complete."
}

function ManageApplicationFlow() {
    SelectApp "manage"
    if [[ -z "$SELECTED_APP_INDEX" ]]; then
        echo "[INFO] Selection cancelled."
        return
    fi
    LoadAppConfig "$SELECTED_APP_INDEX"

    CheckAppStatus
    if [[ "$APP_IS_DEPLOYED" == "1" ]]; then
        if [[ "$CURRENT_TYPE" == "STATIC" ]]; then
            DeployedStaticAppMenu
        else
            DeployedAppMenu
        fi
    else
        NotDeployedAppMenu
    fi
}

function DeployedAppMenu() {
    while true; do
        clear
        echo "============ Manage Deployed Application: $CURRENT_NAME ============"
        echo "  Domain: $CURRENT_DOMAIN (Port: $CURRENT_PORT)"
        [[ -n "$CURRENT_SUBPATH" ]] && echo "  Path:   $CURRENT_SUBPATH"
        echo "  Service File: $CURRENT_SERVICE_FILE"
        echo "------------------------------------------------------------------"
        # Show current status at the top of the menu
        echo -n "Current Status: "
        if systemctl is-active --quiet "$CURRENT_SERVICE_NAME"; then
            echo "● Service is active (running)"
        else
            echo "● Service is inactive (dead)"
        fi
        echo "=================================================================="
        echo
        echo " -- Service Control --"
        echo " 1) Start Service"
        echo " 2) Stop Service"
        echo " 3) Restart Service"
        echo " 4) View Service Status (full)"
        echo " 5) View App Logs (tail -f)"
        echo
        echo " -- Lifecycle Management --"
        echo " 6) Re-run Deployment (Update files and config)"
        echo " 7) View Nginx Config"
        echo " 8) Uninstall Application"
        echo
        echo " 0) Back to Main Menu"
        echo
        read -p "Enter choice: " app_choice

        case "$app_choice" in
            1)
                echo "🚀 Starting service '$CURRENT_SERVICE_NAME'..."
                sudo systemctl start "$CURRENT_SERVICE_NAME"
                sudo systemctl status "$CURRENT_SERVICE_NAME" --no-pager
                press_enter_to_continue
                ;;
            2)
                echo "🛑 Stopping service '$CURRENT_SERVICE_NAME'..."
                sudo systemctl stop "$CURRENT_SERVICE_NAME"
                sudo systemctl status "$CURRENT_SERVICE_NAME" --no-pager
                press_enter_to_continue
                ;;
            3)
                echo "🔁 Restarting service '$CURRENT_SERVICE_NAME'..."
                sudo systemctl restart "$CURRENT_SERVICE_NAME"
                sudo systemctl status "$CURRENT_SERVICE_NAME" --no-pager
                press_enter_to_continue
                ;;
            4)
                sudo systemctl status "$CURRENT_SERVICE_NAME" --no-pager
                press_enter_to_continue
                ;;
            5)
                echo "📜 Tailing logs for '$CURRENT_SERVICE_NAME'. Press CTRL+C to stop."
                sudo journalctl -u "$CURRENT_SERVICE_NAME" -f -n 50
                ;;
            6) DeployApp; return ;;
            7)
                sudo cat "$CURRENT_NGINX_CONF" || echo "Config not found."
                press_enter_to_continue
                ;;
            8) UninstallApp; return ;;
            0) return ;;
            *) echo "[ERROR] Invalid choice."; press_enter_to_continue;;
        esac
    done
}

function DeployedStaticAppMenu() {
     while true; do
        clear
        echo "======== Manage Deployed STATIC Application: $CURRENT_NAME ========="
        echo "  Domain: $CURRENT_DOMAIN"
        echo "  Type:   STATIC"
        echo "  Source: $CURRENT_SOURCE_DIR"
        echo
        echo "  To update, simply replace the files in the source directory."
        echo
        echo " 1) Re-run Deployment (Regenerate Nginx config)"
        echo " 2) View Nginx Config"
        echo " 3) Uninstall Application"
        echo
        echo " 0) Back to Main Menu"
        echo
        read -p "Enter choice: " app_choice

        case "$app_choice" in
            1) DeployApp; return ;;
            2) sudo cat "$CURRENT_NGINX_CONF" || echo "Config not found."; press_enter_to_continue ;;
            3) UninstallApp; return ;;
            0) return ;;
            *) echo "[ERROR] Invalid choice."; press_enter_to_continue ;;
        esac
    done
}

function NotDeployedAppMenu() {
    clear
    echo "======== Manage Application: $CURRENT_NAME (Not Deployed) ========"
    if [[ "$CURRENT_TYPE" == "STATIC" ]]; then
        echo "  Domain: $CURRENT_DOMAIN | Type: STATIC"
    else
        echo "  Domain: $CURRENT_DOMAIN | Port: $CURRENT_PORT"
         [[ -n "$CURRENT_SUBPATH" ]] && echo "  Path:   $CURRENT_SUBPATH"
    fi
    echo
    echo " 1) Deploy Application"
    echo " 0) Back to Main Menu"
    echo
    read -p "Enter choice: " app_choice

    if [[ "$app_choice" == "1" ]]; then
        DeployApp
    elif [[ "$app_choice" == "0" ]]; then
        return
    else
        echo "[ERROR] Invalid choice."
    fi
}

# ============================================================================
# --- CORE LOGIC FUNCTIONS ---
# ============================================================================

function SelectApp() {
    local action_type=$1
    SELECTED_APP_INDEX=""
    clear
    echo "Please select an application to $action_type:"
    echo
    for i in "${!APP_NAMES[@]}"; do
        printf " %2d) %-20s (%-10s on %s)\n" "$((i+1))" "${APP_NAMES[$i]}" "${APP_TYPES[$i]}" "${APP_DOMAINS[$i]}"
    done
    echo
    read -p "Enter number (or 'c' to cancel): " app_choice

    if [[ "$app_choice" =~ ^[0-9]+$ ]] && [[ "$app_choice" -gt 0 ]] && [[ "$app_choice" -le "$APP_COUNT" ]]; then
        SELECTED_APP_INDEX=$((app_choice-1))
    else
        echo "[INFO] Invalid selection or cancelled."
    fi
}

function LoadAppConfig() {
    local index=$1
    CURRENT_NAME="${APP_NAMES[$index]}"
    CURRENT_TYPE="${APP_TYPES[$index]}"
    CURRENT_DOMAIN="${APP_DOMAINS[$index]}"
    CURRENT_PORT="${APP_PORTS[$index]}"
    CURRENT_MODULE="${APP_MODULES[$index]}"
    CURRENT_SUBPATH="${APP_SUBPATHS[$index]}"

    CURRENT_APP_FOLDER="${BASE_APPS_DIR}/${CURRENT_NAME}"
    CURRENT_SOURCE_DIR="${CURRENT_APP_FOLDER}/source"
    CURRENT_VENV_PATH="${CURRENT_APP_FOLDER}/venv"
    CURRENT_SERVICE_NAME="${CURRENT_NAME}.service"
    CURRENT_SERVICE_FILE="${SYSTEMD_DIR}/${CURRENT_SERVICE_NAME}"
    CURRENT_NGINX_CONF="${NGINX_SITES_AVAILABLE}/${CURRENT_DOMAIN}.conf"
}

function CheckAppStatus() {
    APP_IS_DEPLOYED="0"

    # For Python apps, the systemd service is the source of truth
    if [[ "$CURRENT_TYPE" == "ROOT" || "$CURRENT_TYPE" == "SUBDOMAIN" || "$CURRENT_TYPE" == "SUBPATH" ]]; then
        # ROBUST FIX: Use 'systemctl cat' to check if the unit exists.
        # This is not dependent on text formatting like 'list-units' is.
        if systemctl cat "${CURRENT_SERVICE_NAME}" &> /dev/null; then
            APP_IS_DEPLOYED="1"
        fi
    # For STATIC apps, the Nginx config is the source of truth
    elif [[ "$CURRENT_TYPE" == "STATIC" ]]; then
        if [[ -f "$CURRENT_NGINX_CONF" ]]; then
            APP_IS_DEPLOYED="1"
        fi
    fi

    if [[ "$APP_IS_DEPLOYED" == "1" ]]; then
        echo "[INFO] Application '$CURRENT_NAME' appears to be deployed."
    else
        echo "[INFO] Application '$CURRENT_NAME' is not yet deployed."
    fi
}

function DeployApp() {
    echo -e "\n[ACTION] Deploying / Updating application: $CURRENT_NAME"

    if [[ "$CURRENT_TYPE" == "SUBPATH" ]]; then
        if [[ ! -f "$NGINX_SITES_AVAILABLE/${CURRENT_DOMAIN}.conf" ]]; then
            echo "[ERROR] Cannot deploy SUBPATH app '$CURRENT_NAME'."
            echo "         Its parent domain '$CURRENT_DOMAIN' does not have a deployed Nginx config."
            echo "         Please deploy the main app for '$CURRENT_DOMAIN' first."
            return
        fi
    fi

    echo "How do you want to configure SSL?"
    echo " 1. HTTP only (no SSL)"
    echo " 2. HTTPS (use existing/generate new certificate for $CURRENT_DOMAIN)"
    echo " 3. HTTPS (use existing WILDCARD certificate for *.${ROOT_DOMAIN})"
    read -p "Enter choice [1]: " SSL_CHOICE
    [[ -z "$SSL_CHOICE" ]] && SSL_CHOICE=1

    if [[ "$SSL_CHOICE" == "2" ]]; then
        ObtainCertificate "$CURRENT_DOMAIN"
        if [[ $? -ne 0 ]]; then
             echo "[ERROR] Failed to obtain certificate. Aborting deployment."
             return
        fi
    fi

    echo "[TASK] Creating application directories..."
    mkdir -p "$CURRENT_SOURCE_DIR"
    sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "$CURRENT_APP_FOLDER"

    if [[ "$CURRENT_TYPE" == "STATIC" ]]; then
        echo "[INFO] Static site deployment. Skipping Python/systemd setup."
        if [[ ! -f "${CURRENT_SOURCE_DIR}/index.html" ]]; then
            echo "<h1>Welcome to $CURRENT_NAME</h1><p>Replace this with your static content.</p>" > "${CURRENT_SOURCE_DIR}/index.html"
            echo "[INFO] Created placeholder index.html."
        fi
    else
        echo "[TASK] Setting up Python virtual environment..."
        if [[ ! -d "$CURRENT_VENV_PATH" ]]; then
            python3 -m venv "$CURRENT_VENV_PATH"
        fi

        echo "[TASK] Installing/updating Python packages..."

        # 1. Always ensure gunicorn is installed in the venv for the service to run.
        echo "[INFO] Installing/upgrading deployment server (gunicorn)..."
        "${CURRENT_VENV_PATH}/bin/pip" install --upgrade pip gunicorn

        # 2. Check for requirements.txt in the SOURCE directory, which is more common.
        local req_file="${CURRENT_SOURCE_DIR}/requirements.txt"
        if [[ -f "$req_file" ]]; then
            echo "[INFO] Found 'requirements.txt'. Installing application packages..."
            "${CURRENT_VENV_PATH}/bin/pip" install -r "$req_file"
        else
            # Also check the parent folder, just in case.
            req_file="${CURRENT_APP_FOLDER}/requirements.txt"
            if [[ -f "$req_file" ]]; then
                echo "[INFO] Found 'requirements.txt'. Installing application packages..."
                "${CURRENT_VENV_PATH}/bin/pip" install -r "$req_file"
            else
                echo "[WARNING] 'requirements.txt' not found in source or app directory. Skipping app packages."
            fi
        fi

        echo "[TASK] Creating/Updating systemd service file: $CURRENT_SERVICE_FILE"
        sudo tee "$CURRENT_SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Gunicorn instance to serve $CURRENT_NAME
After=network.target

[Service]
User=$DEPLOY_USER
Group=www-data
WorkingDirectory=$CURRENT_APP_FOLDER
Environment="PATH=$CURRENT_VENV_PATH/bin"
ExecStart=$CURRENT_VENV_PATH/bin/gunicorn --workers 3 --bind 127.0.0.1:$CURRENT_PORT $CURRENT_MODULE

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable "$CURRENT_SERVICE_NAME"
    fi

    echo "[TASK] Generating Nginx configuration for domain '$CURRENT_DOMAIN'..."
    GenerateNginxConfigFileForDomain "$CURRENT_DOMAIN" "$SSL_CHOICE"

    if [[ "$CURRENT_TYPE" == "ROOT" || ( "$CURRENT_TYPE" == "STATIC" && "$CURRENT_DOMAIN" == "$ROOT_DOMAIN" ) ]]; then
        DisableDefaultNginxConfig
    fi

    echo
    echo "[SUCCESS] Deployment/update complete for $CURRENT_NAME."
    echo "You may need to:"
    echo " - Reload Nginx to apply the new site config (Menu 2)."
    echo " - Start the '$CURRENT_NAME' service (if applicable)."
}

function GenerateNginxConfigFileForDomain() {
    local target_domain=$1
    local ssl_mode=$2
    local conf_file="${NGINX_SITES_AVAILABLE}/${target_domain}.conf"
    echo "[INFO] Generating Nginx config for domain: $target_domain"

    local use_https=0
    if [[ "$ssl_mode" == "2" || "$ssl_mode" == "3" ]]; then
        use_https=1
    fi

    # Find the primary app (ROOT, SUBDOMAIN, or STATIC) for this domain
    local primary_app_port=""
    local primary_app_type=""
    local primary_app_source_dir=""
    local primary_app_name=""
    local primary_app_index=-1

    for i in "${!APP_DOMAINS[@]}"; do
        if [[ "${APP_DOMAINS[$i]}" == "$target_domain" ]]; then
            local type="${APP_TYPES[$i]}"
            if [[ "$type" == "ROOT" || "$type" == "SUBDOMAIN" || "$type" == "STATIC" ]]; then
                primary_app_port="${APP_PORTS[$i]}"
                primary_app_type="${APP_TYPES[$i]}"
                primary_app_name="${APP_NAMES[$i]}"
                primary_app_source_dir="${BASE_APPS_DIR}/${APP_NAMES[$i]}/source"
                primary_app_index=$i
                break # Found the one primary app for this domain
            fi
        fi
    done

    if [[ -z "$primary_app_name" ]]; then
        echo "[ERROR] Could not find a primary app [ROOT, SUBDOMAIN, or STATIC] for domain '$target_domain'."
        return 1
    fi
    echo "[INFO] Primary app for this domain is '$primary_app_name' (Type: $primary_app_type)"

    # Create the config using a heredoc
    {
        # --- HTTP to HTTPS Redirect Block ---
        if (( use_https )); then
            echo "# HTTP to HTTPS redirect"
            echo "server {"
            echo "    listen 80;"
            echo "    server_name $target_domain;"
            echo "    return 301 https://\$host\$request_uri;"
            echo "}"
            echo ""
        fi

        # --- Main Server Block ---
        echo "# Main Server Block for $target_domain"
        echo "server {"
        if (( use_https )); then
            echo "    listen 443 ssl http2;"
            echo "    server_name $target_domain;"
            local cert_domain=$target_domain
            if [[ "$ssl_mode" == "3" ]]; then
                cert_domain=$ROOT_DOMAIN
                echo "    # Using Wildcard Certificate"
            fi
            echo "    ssl_certificate /etc/letsencrypt/live/$cert_domain/fullchain.pem;"
            echo "    ssl_certificate_key /etc/letsencrypt/live/$cert_domain/privkey.pem;"
            echo "    include $SSL_OPTIONS_FILE;"
            echo "    ssl_dhparam $SSL_DHPARAMS_FILE;"
        else
            echo "    listen 80;"
            echo "    server_name $target_domain;"
        fi
        echo ""

        # --- Primary App Location Block ---
        if [[ "$primary_app_type" == "STATIC" ]]; then
            echo "    # Location for the primary STATIC app: $primary_app_name"
            echo "    root $primary_app_source_dir;"
            echo "    index index.html index.htm;"
            echo "    location / {"
            echo "        try_files \$uri \$uri/ /index.html;"
            echo "    }"
        else
            echo "    # Location for the primary Python app: $primary_app_name"
            echo "    location / {"
            echo "        proxy_pass http://127.0.0.1:$primary_app_port;"
            echo "        proxy_set_header Host \$host;"
            echo "        proxy_set_header X-Real-IP \$remote_addr;"
            echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
            echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
            echo "    }"
        fi

        # --- Subpath App Location Blocks ---
        for i in "${!APP_DOMAINS[@]}"; do
            # Check for SUBPATH app on the right domain, AND that it's NOT the primary app we just configured
            if [[ "${APP_DOMAINS[$i]}" == "$target_domain" && "${APP_TYPES[$i]}" == "SUBPATH" && "$i" -ne "$primary_app_index" ]]; then
                echo ""
                echo "    # Location block for Subpath App: ${APP_NAMES[$i]}"
                echo "    location ${APP_SUBPATHS[$i]}/ {"
                echo "        proxy_pass http://127.0.0.1:${APP_PORTS[$i]}/;"
                echo "        proxy_set_header Host \$host;"
                echo "        proxy_set_header X-Real-IP \$remote_addr;"
                echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
                echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
                echo "    }"
            fi
        done

        echo "}"
    } | sudo tee "$conf_file" > /dev/null

    # Enable the site by creating a symlink
    sudo ln -sf "$conf_file" "$NGINX_SITES_ENABLED/"
    echo "[SUCCESS] Nginx config written to $conf_file and enabled."
}

function UninstallApp() {
    echo -e "\n[ACTION] Uninstalling application: $CURRENT_NAME"

    # --- Check for dependent SUBPATH apps ---
    if [[ "$CURRENT_TYPE" == "ROOT" || "$CURRENT_TYPE" == "SUBDOMAIN" || "$CURRENT_TYPE" == "STATIC" ]]; then
        local dependent_apps=""
        for i in "${!APP_DOMAINS[@]}"; do
            if [[ "${APP_DOMAINS[$i]}" == "$CURRENT_DOMAIN" && "${APP_TYPES[$i]}" == "SUBPATH" ]]; then
                dependent_apps+="${APP_NAMES[$i]} "
            fi
        done
        if [[ -n "$dependent_apps" ]]; then
            echo "[ERROR] Cannot uninstall $CURRENT_NAME. It is the primary domain for other apps."
            echo "         Dependent SUBPATH apps found: $dependent_apps"
            echo "         Please uninstall the SUBPATH apps first."
            return
        fi
    fi

    echo "This will remove the systemd service and Nginx config."
    echo "It will NOT delete the application source code or venv."
    read -p "Are you sure you want to uninstall $CURRENT_NAME? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Uninstall cancelled."
        return
    fi

    if [[ "$CURRENT_TYPE" != "STATIC" ]]; then
        echo "[TASK] Stopping and disabling systemd service..."
        sudo systemctl stop "$CURRENT_SERVICE_NAME" &> /dev/null
        sudo systemctl disable "$CURRENT_SERVICE_NAME" &> /dev/null
        echo "[TASK] Removing systemd service file..."
        sudo rm -f "$CURRENT_SERVICE_FILE"
        sudo systemctl daemon-reload
    fi

    echo "[TASK] Updating Nginx configuration..."
    if [[ "$CURRENT_TYPE" == "SUBPATH" ]]; then
        echo "[IMPORTANT] This is a SUBPATH app. Its service has been removed."
        echo "            To remove it from the Nginx configuration, you MUST"
        echo "            re-run the 'Deploy' action for its parent domain:"
        echo "            '$CURRENT_DOMAIN'"
        echo "            This ensures the parent app's SSL settings are preserved correctly."
    else
        echo "[INFO] This is a primary app. Removing its Nginx config file and symlink..."
        sudo rm -f "${NGINX_SITES_AVAILABLE}/${CURRENT_DOMAIN}.conf"
        sudo rm -f "${NGINX_SITES_ENABLED}/${CURRENT_DOMAIN}.conf"
        if [[ "$CURRENT_TYPE" == "ROOT" || ( "$CURRENT_TYPE" == "STATIC" && "$CURRENT_DOMAIN" == "$ROOT_DOMAIN" ) ]]; then
            RestoreDefaultNginxConfigIfNeeded "$CURRENT_NAME"
        fi
    fi

    echo
    echo "[SUCCESS] $CURRENT_NAME has been uninstalled."
    echo "[INFO] Please reload Nginx or run 'Sync and Clean' to apply changes."
}

# ============================================================================
# --- UTILITY AND SYSTEM FUNCTIONS ---
# ============================================================================

function ManageNginxMenu() {
    while true; do
        clear
        echo "============ Manage Nginx Service ============="
        echo -n "Current Status: "
        if systemctl is-active --quiet nginx; then
            echo "● Nginx is active (running)"
        else
            echo "● Nginx is inactive (dead)"
        fi
        echo "-----------------------------------------------"
        echo " 1) Start Nginx"
        echo " 2) Stop Nginx"
        echo " 3) Reload Nginx Config"
        echo " 4) Test Nginx Configuration"
        echo " 0) Back to Main Menu"
        read -p "Enter choice: " nginx_choice

        case "$nginx_choice" in
            1)
                echo "🚀 Starting Nginx..."; sudo systemctl start nginx
                sudo systemctl status nginx --no-pager; press_enter_to_continue
                ;;
            2)
                echo "🛑 Stopping Nginx..."; sudo systemctl stop nginx
                sudo systemctl status nginx --no-pager; press_enter_to_continue
                ;;
            3)
                echo "🔁 Reloading Nginx..."
                echo "Testing config first..."
                if sudo nginx -t; then
                    echo "Config OK. Reloading service..."
                    sudo systemctl reload nginx
                    sudo systemctl status nginx --no-pager
                else
                    echo "[ERROR] Nginx config test failed. Aborting reload."
                fi
                press_enter_to_continue
                ;;
            4)
                echo "🧪 Testing Nginx Configuration..."; sudo nginx -t
                press_enter_to_continue
                ;;
            0) return ;;
            *) echo "[ERROR] Invalid choice."; press_enter_to_continue;;
        esac
    done
}

function ManageSslMenu() {
    while true; do
        clear
        echo "================== Manage SSL Certificates =================="
        echo " 1) Renew All Existing Certificates"
        echo " 2) Obtain/Renew a Wildcard Certificate (Interactive DNS)"
        echo " 0) Back to Main Menu"
        read -p "Enter choice: " ssl_choice

        case "$ssl_choice" in
            1)
                echo "Stopping Nginx..."; sudo systemctl stop nginx
                sudo certbot renew
                echo "Restarting Nginx..."; sudo systemctl start nginx
                echo "Done."
                press_enter_to_continue
                 ;;
            2) ObtainWildcardCert; press_enter_to_continue ;;
            0) return ;;
            *) echo "[ERROR] Invalid choice."; press_enter_to_continue ;;
        esac
    done
}

function SyncAndClean() {
    echo "[ACTION] Syncing Nginx configs with registered apps..."
    declare -A registered_confs
    # Populate the associative array with all valid primary domain configs
    for i in "${!APP_TYPES[@]}"; do
        type="${APP_TYPES[$i]}"
        if [[ "$type" == "ROOT" || "$type" == "SUBDOMAIN" || "$type" == "STATIC" ]]; then
            conf_name="${APP_DOMAINS[$i]}.conf"
            registered_confs["$conf_name"]=1
        fi
    done
    # Add the default config to the list of ones to keep
    registered_confs["00-default"]=1

    echo "[INFO] Verifying enabled sites..."
    for conf_path in ${NGINX_SITES_ENABLED}/*; do
        if [[ -L "$conf_path" ]]; then # Check if it's a symlink
            conf_file=$(basename "$conf_path")
            # If the symlink is NOT in our list of valid configs, remove it
            if [[ -z "${registered_confs[$conf_file]}" ]]; then
                echo "[CLEANUP] Found orphaned config symlink: $conf_file. Removing..."
                sudo rm "$conf_path"
            fi
        fi
    done

    echo "[SUCCESS] Cleanup complete. Reload Nginx to apply changes."
}

function ObtainCertificate() {
    local domain_to_cert=$1
    echo "[ACTION] Obtaining certificate for $domain_to_cert"
    read -p "This will stop Nginx temporarily. Proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "[INFO] Certificate generation cancelled."
        return 1
    fi
    sudo systemctl stop nginx
    if ! sudo certbot certonly --standalone -d "$domain_to_cert" --non-interactive --agree-tos -m "$CERTBOT_EMAIL"; then
        echo "[ERROR] Certbot failed. Please check the output above."
        sudo systemctl start nginx # Always restart nginx
        return 1
    fi
    sudo systemctl start nginx
    echo "[SUCCESS] Certificate obtained for $domain_to_cert."
    return 0
}

function ObtainWildcardCert() {
    echo "[ACTION] Obtaining wildcard certificate for *.${ROOT_DOMAIN}"
    echo "[INFO] This requires creating a DNS TXT record. Nginx will be stopped."
    read -p "Proceed? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "[INFO] Operation cancelled."
        return
    fi

    sudo systemctl stop nginx
    echo "=========================== DNS ACTION REQUIRED ==========================="
    echo "  Certbot will now show you a TXT record to create in your DNS panel."
    echo "  After creating it, wait a few minutes, then press Enter here."
    echo "==========================================================================="
    # Run certbot and check its exit code
    if ! sudo certbot certonly --manual --preferred-challenges=dns -d "*.${ROOT_DOMAIN}" -d "${ROOT_DOMAIN}" --agree-tos -m "${CERTBOT_EMAIL}"; then
        echo "[ERROR] Certbot failed. Check the output above."
    else
        echo "[SUCCESS] Certbot process completed."
    fi
    echo "[INFO] Restarting Nginx..."
    sudo systemctl start nginx
}

function DisableDefaultNginxConfig() {
    local default_conf_link="${NGINX_SITES_ENABLED}/00-default"
    if [[ -L "$default_conf_link" ]]; then # Check if it's a symlink
        echo "[INFO] Disabling default Nginx welcome page..."
        sudo rm "$default_conf_link"
    fi
}

function RestoreDefaultNginxConfigIfNeeded() {
    local uninstalled_app_name=$1
    local another_root_exists=0
    for i in "${!APP_TYPES[@]}"; do
        # Check if another app is a ROOT type, OR a STATIC type on the root domain
        if [[ ( "${APP_TYPES[$i]}" == "ROOT" || "${APP_TYPES[$i]}" == "STATIC" ) && "${APP_DOMAINS[$i]}" == "$ROOT_DOMAIN" ]]; then
            if [[ "${APP_NAMES[$i]}" != "$uninstalled_app_name" ]]; then
                another_root_exists=1
                break
            fi
        fi
    done

    if (( another_root_exists )); then
        echo "[INFO] Another ROOT/STATIC application still exists on the root domain. Default page will remain disabled."
    else
        echo "[INFO] No other ROOT/STATIC applications found on the root domain. Re-enabling default Nginx page."
        sudo ln -sf "${NGINX_SITES_AVAILABLE}/00-default" "${NGINX_SITES_ENABLED}/00-default"
    fi
}

# ============================================================================
# --- SCRIPT ENTRY POINT ---
# ============================================================================
MainMenu