# 🖥️ Windows Single-App Manager Guide

This guide provides detailed instructions for using the `single_app_manager_windows_v1.bat` script to deploy and manage a **single Python web application** on a Windows Server.

This script is ideal for a simple, dedicated server environment where you need to host one primary website or API. It automates the entire stack: Nginx (web server), Waitress (application server), NSSM (service manager), and Certbot (SSL).

**Target Script:** `Windows/single_app_manager_windows_v1.bat`

---

## 📂 Prerequisites & Folder Structure

Before you begin, you must set up your folder structure correctly. The script relies on finding specific installer files in a subfolder named `installers`.

1.  **Run as Administrator:** The script requires administrative privileges to install software and manage Windows services. It will attempt to self-elevate if not run as an admin.
2.  **Create an `installers` folder** in the same directory as the `.bat` script.
3.  **Download and place the following files** into the `installers` folder:
    *   **Python:** The latest `python.exe` installer (e.g., `python-3.12.3-amd64.exe`).
    *   **Nginx:** The latest mainline version `nginx.zip` file (e.g., `nginx-1.27.4.zip`).
    *   **NSSM:** The latest release `nssm.zip` file (e.g., `nssm-2.24.zip`).

Your folder should look like this:

```
your_project_folder/
├── single_app_manager_windows_v1.bat
└── installers/
    ├── python-3.12.3-amd64.exe
    ├── nginx-1.27.4.zip
    └── nssm-2.24.zip
```
> ✅ **Important:** The script automatically finds the files by their name pattern (e.g., `python-*.exe`), so the exact version numbers in the filenames do not matter.

---

## ⚙️ Configuration

Before running the script for the first time, you **must** edit the configuration variables at the top of the `single_app_manager_windows_v1.bat` file.

```batch
:: === CONFIGURATION ===
set "DOMAIN=yourdomain.com"
set "APP_NAME=AppName"
set "PORT=8000"

set "EMAIL=admin@%DOMAIN%"
set "ACTIVE_DRIVE=C:"

:: --- Paths for Existing SSL Certificates ---
set "EXISTING_CERT_PATH=%ACTIVE_DRIVE%\certs\%DOMAIN%\fullchain.pem"
set "EXISTING_KEY_PATH=%ACTIVE_DRIVE%\certs\%DOMAIN%\privkey.key"

set "MODULE=source:create_app"
```

*   `DOMAIN`: The public domain name for your application (e.g., `myapp.com`).
*   `APP_NAME`: A descriptive name for your application. This will be used for the folder name (e.g., `C:\AppName`) and the service name.
*   `PORT`: The local port your Python app will listen on (e.g., `8000`). Nginx will proxy requests to this port. **This port is not exposed to the public.**
*   `MODULE`: The Python import path for your application's factory function (e.g., `your_package:create_app`).
*   `EXISTING_CERT_PATH` / `EXISTING_KEY_PATH`: **(Optional)** If you are using your own SSL certificates (Option 2), update these paths to point to your certificate and private key files.

---

## ▶️ Recommended First-Time Setup

Follow these steps to get your server running from scratch.

1.  **Configure & Prepare:**
    *   Edit the variables at the top of the script.
    *   Place the required installers in the `installers` folder.

2.  **Run as Administrator:** Right-click `single_app_manager_windows_v1.bat` and select "Run as Administrator".

3.  **Step 1: Bootstrap the Server (Option 0)**
    *   Select `0` and press Enter. The script will install Python, Nginx, NSSM, Certbot, and configure the Windows Firewall.
    *   > ⚠️ **Action Required:** After the bootstrap process installs Python or Certbot, you **MUST close and re-open the script** for the system's PATH variable to update.

4.  **Step 2: Deploy Application Code**
    *   The script creates an application directory (e.g., `C:\AppName`).
    *   Place your application's source code inside this folder.
    *   Create a `requirements.txt` file in `C:\AppName\requirements.txt` listing all Python dependencies (e.g., `Flask`, `waitress`). The script will install these automatically during bootstrap.

5.  **Step 3: Set up SSL (Option 1 or 2)**
    *   **Option 1 (Let's Encrypt):** Fetches a new certificate. Requires your domain's DNS to point to the server and port 80 to be open.
    *   **Option 2 (Existing Certs):** Uses certificate files you provide. Ensure the paths are correct in the script's configuration.

6.  **Step 4: Install and Start Services**
    *   Run **Option 6 (Install/Update App Service)**. This creates the Windows service for your Python app.
    *   Run **Option 7 (Start App Service)** to start your Python application.
    *   Run **Option 3 (Start/Enable Nginx Service)** to start the web server.

Your site is now live and accessible at `https://yourdomain.com`.

---

## 📜 Menu Options Explained

This script provides a simple, flat menu to manage all aspects of the deployment.

#### System and Dependencies
*   `0) Bootstrap Server`: **Run this first.** Installs all software and prepares the system.
*   `1) Setup SSL with Certbot`: Gets a new, free SSL certificate from Let's Encrypt.
*   `2) Setup SSL with Existing Certificates`: Uses SSL certificate files you already have.

#### Nginx Web Server
*   `3) Start/Enable Nginx Service`: Starts the Nginx web server.
*   `4) Stop/Disable Nginx Service`: Stops the Nginx web server.
*   `5) Reload Nginx Config`: Safely restarts Nginx to apply any configuration changes.

#### Python Application
*   `6) Install/Update App Service`: Creates or updates the Windows service for your Python app.
*   `7) Start App Service`: Starts your Python application's service.
*   `8) Stop App Service`: Stops your Python application's service.
*   `9) Restart App Service`: The quickest way to apply new code changes.
*   `10) View App Logs`: Shows a live view of your application's log file. Essential for debugging.
*   `11) View App Status`: Checks if the application service is running or stopped.
*   `12) Uninstall App Service`: Cleanly removes the application's Windows service.

---

## 🧠 Manual Commands & Troubleshooting

If you need to manually interact with the services or check ports, these commands are helpful.

#### Service Control (via Command Prompt)
```cmd
:: Check status of Nginx or your app
nssm status nginx
nssm status AppName

:: Start a service
nssm start AppName
```

#### Check for Port Usage
To see what process is using a specific port (e.g., port 80):
```cmd
netstat -ano -p TCP | findstr ":80"
```
Use the PID (Process ID) from the output with `tasklist` to find the application name.

#### Live Log Viewing (via PowerShell)
The script uses this command for log viewing. You can run it manually in PowerShell:
```powershell
Get-Content -Path C:\AppName\logs\app.log -Wait -Tail 20
```
*(Replace `AppName` with your application's name.)*
