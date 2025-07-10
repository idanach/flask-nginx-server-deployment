
# 🖥️ Linux Server Guide for Flask App Deployment

This guide covers how to work with a Linux server (Ubuntu-based) to deploy, manage, and troubleshoot your Flask-based web app using a single powerful tool: `app_manager_linux.sh`.

---

## 🚀 Deployment Tool: `app_manager_linux.sh`

This is your all-in-one command center for managing your app server.

### 📦 What It Can Do:

```text
0) Bootstrap base system      → Install Python, set timezone, prep the OS
1) Setup nginx + SSL          → Configure nginx, issue HTTPS cert with Let's Encrypt
2) Start app                  → Create + start Gunicorn systemd service
3) Stop app                   → Stop and disable the systemd app service
4) Restart app                → Restart the running Flask app
5) View app logs              → Tail system logs live
6) Check app status           → See whether the app service is running
```

### ▶️ How to Use It

```bash
chmod +x app_manager_linux.sh
./app_manager_linux.sh
```

Choose the action by number and follow the prompts.

---

## 📁 App Folder Structure

Your app should be located at:

```
/home/ubuntu/AppName/
├── venv/                   # Python virtual environment
├── source/                 # Flask app module
│   └── __init__.py         # Includes create_app()
├── manage_app.sh           # This script (optional alias)
└── requirements.txt
```

Make sure your `source/__init__.py` has this function:

```python
def create_app():
    app = Flask(__name__)
    ...
    return app
```

---

## 🧠 Useful Linux Commands

### 🔒 Permissions
```bash
sudo chown -R ubuntu:ubuntu ~/AppName
sudo chmod -R 775 ~/AppName
```

### Open ports
```
sudo iptables -I INPUT -p tcp --dport 5000 -j ACCEPT  # Flask
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT    # HTTP
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT   # HTTPS (optional)
sudo iptables -I INPUT -p tcp --dport 3389 -j ACCEPT  # RDP (if using GUI)

sudo iptables -L
```

### 🔥 Service Control
```bash
sudo systemctl start AppName
sudo systemctl stop AppName
sudo systemctl restart AppName
sudo systemctl status AppName
```

### 📡 Port Check
```bash
sudo lsof -i :8000
```

### 📝 Live Logs
```bash
journalctl -u AppName -f
```

### 🧪 Test Site
```bash
curl -I https://doamin.com
```

---

## 💡 Recommended Practices

- Always use `venv` to isolate dependencies `source venv/bin/activate`.
- Keep your system updated: `sudo apt update && sudo apt upgrade -y`
- Use `ufw` to control access:
  ```bash
  sudo ufw allow OpenSSH
  sudo ufw allow 'Nginx Full'
  sudo ufw enable
  ```
- Reboot after base setup: `sudo reboot`

---

## ✅ After First Setup

Once you've used option 0 to bootstrap and option 1 to set up nginx + SSL, you can:

- Deploy updated code → `git pull` or re-upload
- Restart the app → `./app_manager_linux.sh` then choose `4`
- View logs or check app status → options `5` and `6`

This script is designed to make Linux server management simple, even if you're not using it every day.

---

## 🔗 Domain & SSL

Make sure your domain (e.g. `domain.com`) points to your public IP before running SSL setup. Use your DNS manager to set an A record if needed.

---

## 🧰 Advanced (Optional)

- Add a cron job to renew SSL:
  ```bash
  sudo crontab -e
  0 3 * * * certbot renew --quiet && systemctl reload nginx
  ```
- Create an alias:
  ```bash
  echo "alias appman='~/AppName/app_manager_linux.sh'" >> ~/.bashrc && source ~/.bashrc
  ```

---

## 🙌 Done!

This setup has you covered from VM creation to full app deployment and live SSL site, all through one script.






---

# 🖥️ Windows Server Guide for Flask App Deployment

This guide covers how to work with a Windows server to deploy, manage, and troubleshoot your Flask-based web app using a single powerful tool: `app_manager_windows.bat`.

---

## 🚀 Deployment Tool: `app_manager_windows.bat`

This is your all-in-one command center for managing your app server. It is designed to be run as an Administrator and will automatically handle installation, configuration, and service management for the entire web stack.

### 📦 What It Can Do:

```text
0) Bootstrap Server         → Install Python, Nginx, NSSM, Certbot & set firewall rules
1) Setup SSL with Certbot    → Fetch a new SSL certificate from Let's Encrypt
2) Setup SSL with Existing   → Use certificate files you already have

3) Start Nginx Service       → Start the web server
4) Stop Nginx Service        → Stop the web server
5) Reload Nginx Config       → Safely restart Nginx to apply config changes

6) Install/Update App Service→ Create/update the Python app's Windows service
7) Start App Service         → Start the Flask application
8) Stop App Service          → Stop the Flask application
9) Restart App Service       → Restart the running Flask app
10) View App Logs            → Tail application logs live
11) View App Status          → See if the app service is running
12) Uninstall App Service    → Cleanly remove the app service
```

### ▶️ How to Use It

1.  **Prepare the `installers` folder** (see below).
2.  **Right-click `app_manager_windows.bat`** and choose **"Run as Administrator"**.
3.  Choose the action by number from the menu and follow the prompts.

---

## 📁 Required Folder Structure

Before running the script, place it and its required installers into a single folder like this:

```
your_folder/
├── app_manager_windows.bat
└── installers/
    ├── python-3.12.3-amd64.exe
    ├── nssm-2.24.zip
    └── nginx-1.27.4.zip
```
> ✅ **Important:** The script automatically finds the files inside `installers` by name (e.g., `python-*.exe`), so exact version numbers in the filenames do not matter.

---

## ⚙️ How the Script Works

The script installs all software to a configurable drive (default is `C:`).

*   **Python App:** `C:\PMAlchemyV4.1\` (includes `venv/` and `logs/`)
*   **Nginx:** `C:\nginx\`
*   **NSSM:** `C:\nssm\`
*   **Certbot Data:** `C:\Certbot\`

Your Flask app's Python dependencies should be listed in `C:\PMAlchemyV4.1\requirements.txt`. The bootstrap process will install them automatically.

Make sure your `source\__init__.py` has a factory function like this:
```python
# In source/__init__.py
from flask import Flask

def create_app():
    app = Flask(__name__)
    # ... your routes and logic ...
    return app
```

---

## 🧠 Useful Windows Commands (Manual Equivalents)

### 🔥 Service Control (using `nssm` or `sc`)
```cmd
nssm status nginx
nssm start PMAlchemyV4.1

sc query nginx
sc start PMAlchemyV4.1
```

### 📡 Port Check
Find what's using port 80:
```cmd
netstat -ano -p TCP | findstr ":80"
tasklist /FI "PID eq <PID_FROM_PREVIOUS_COMMAND>"
```

### 📝 Live Logs
```powershell
# This is what the script's log viewer runs
Get-Content -Path C:\PMAlchemyV4.1\logs\app.log -Wait -Tail 10
```

### 🧪 Test Site
After setup, check the site from a browser on the server:
```
http://localhost
```
Or after SSL setup:
```
https://domain.com
```

---

## 💡 Recommended First-Time Setup

1.  Place required installers in the `installers` folder.
2.  Run the script as Administrator and choose **Option 0**. This will install Python, Nginx, NSSM, Certbot (via pip), and configure the firewall. **You may need to restart the terminal after this step.**
3.  Choose your SSL method:
    *   **Option 1** to fetch a live certificate from Let's Encrypt (requires a public domain and open ports).
    *   **Option 2** to use certificate files you've placed on the server manually.
4.  Choose **Option 6** to install your Python application as a Windows service.
5.  Choose **Option 7** to start your app service.
6.  Choose **Option 3** to start the Nginx service.

Your site is now live!

---

## 🔗 Domain & SSL Notes

*   **For Certbot (Option 1):** Before running, make sure your domain's DNS "A" record points to your server's public IP address. Your firewall and router must allow traffic on **port 80** from the public internet.
*   **For Existing Certs (Option 2):** Before running, place your `fullchain.pem` and `privkey.key` files in the location specified by the `EXISTING_CERT_PATH` and `EXISTING_KEY_PATH` variables at the top of the script.

---

## 🙌 Done!

This script provides a complete, automated solution for deploying a production-ready Flask application on a Windows server, covering everything from initial setup to ongoing management and SSL configuration.