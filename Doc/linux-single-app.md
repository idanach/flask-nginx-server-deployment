# 🖥️ Linux Single-App Manager Guide

This guide provides detailed instructions for using the `single_app_manager_linux_v1.sh` script to deploy and manage a **single Python web application** on a Linux server (Debian/Ubuntu-based).

This script is perfect for a simple, dedicated server setup. It automates the installation and configuration of the full web stack: Nginx (web server), Gunicorn (application server), systemd (service manager), UFW (firewall), and Certbot (SSL).

**Target Script:** `Linux/single_app_manager_linux_v1.sh`

---

## 📂 Prerequisites

1.  **Debian/Ubuntu Server:** This script is designed for distributions that use the `apt` package manager.
2.  **Sudo User:** You must run this script as a non-root user with `sudo` privileges (e.g., the default `ubuntu` user on an AWS EC2 instance).
3.  **Application Code:** Have your Python application source code ready to be placed on the server.

---

## ⚙️ Configuration

Before running the script for the first time, you **must** edit the configuration variables at the top of the `single_app_manager_linux_v1.sh` file.

```bash
#!/bin/bash

set -e

DOMAIN="domain.com"
APP_NAME="AppName"
PORT="8000"

EMAIL="admin@$DOMAIN"
APP_DIR="/home/ubuntu/$APP_NAME"
VENV_PATH="$APP_DIR/venv"
MODULE="source:create_app()"
```

*   `DOMAIN`: The public domain name for your application (e.g., `myapp.com`).
*   `APP_NAME`: A descriptive name for your application. This determines the service name (`AppName.service`) and the directory (`/home/ubuntu/AppName`).
*   `PORT`: The local port your Python app will listen on (e.g., `8000`). Nginx will proxy requests to this port. **This port is not exposed to the public.**
*   `EMAIL`: Your email address, used for Let's Encrypt SSL notifications.
*   `MODULE`: The Gunicorn-compatible import path to your WSGI application callable (e.g., `source:create_app()` for a factory pattern, or `main:app` for a simple app object).

---

## ▶️ Recommended First-Time Setup

Follow these steps to get your server running from scratch.

1.  **Place and Configure Script:**
    *   Upload the `single_app_manager_linux_v1.sh` script to your server (e.g., into your home directory).
    *   Make it executable: `chmod +x single_app_manager_linux_v1.sh`.
    *   Edit the variables at the top of the script using `nano` or `vim`.

2.  **Run the Script:** `./single_app_manager_linux_v1.sh`.

3.  **Step 1: Bootstrap the Server (Option 0)**
    *   Select `0` and press Enter. The script will update the system and install base packages like `python3-venv`.

4.  **Step 2: Deploy Application Code**
    *   Create the application directory: `mkdir -p /home/ubuntu/AppName`.
    *   Upload your application source code into that directory.
    *   Create a `requirements.txt` file listing all Python dependencies. **Make sure `gunicorn` is included in this file.**

5.  **Step 3: Set up Nginx & SSL (Option 1)**
    *   Select `1` and press Enter. This is a critical step that:
        *   Installs Nginx, Certbot, and UFW.
        *   Configures an Nginx site to proxy traffic to your app.
        *   Fetches and installs a free SSL certificate from Let's Encrypt.
        *   Configures the firewall to allow `Nginx Full` (ports 80/443) and `OpenSSH`.
    *   This requires your domain's DNS "A" record to be pointing to your server's public IP.

6.  **Step 4: Install and Start Application Service (Option 2)**
    *   Before running this, you must set up the virtual environment and install dependencies:
        ```bash
        cd /home/ubuntu/AppName
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
        deactivate
        ```
    *   Now, run **Option 2** in the script. It will create a `systemd` service file for your app and start it automatically.

Your site is now live! You can access it at `https://yourdomain.com`.

---

## 📜 Menu Options Explained

*   `0) Bootstrap base system`: **Run this first.** Updates the server and installs core Python tools.
*   `1) Setup nginx + SSL`: Installs the web server, firewall, and SSL components. Configures them for your domain.
*   `2) Start app`: Creates and starts the `systemd` service that runs your Python application via Gunicorn.
*   `3) Stop app`: Stops and disables your application's `systemd` service.
*   `4) Restart app`: The quickest way to apply new code changes. Restarts the Gunicorn service.
*   `5) View app logs`: Shows a live-tail of your application's logs using `journalctl`. Essential for debugging.
*   `6) Check app status`: Shows the detailed status of your application's `systemd` service.

---

## 🧠 Manual Commands & Troubleshooting

If you need to interact with the server outside of the script, these commands are useful.

#### Service Control (systemd)
```bash
# Check the status of your app or nginx
sudo systemctl status AppName
sudo systemctl status nginx

# Restart your app service
sudo systemctl restart AppName
```

#### Live Log Viewing (journalctl)
```bash
# Tail the logs for your application
sudo journalctl -u AppName -f
```

#### Firewall Status (UFW)
```bash
# See active rules and status
sudo ufw status verbose
```

#### Test Site from Command Line
```bash
# Check if the server is responding correctly
curl -I https://yourdomain.com
```
You should see `HTTP/2 200` or a similar success status code in the response headers.
