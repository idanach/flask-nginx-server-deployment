
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





# 🖥️ Windows Offline Flask App Deployment Guide

This guide walks you through deploying and managing your Flask app on a **Windows machine with no internet access**, using `app_manager_windows.bat`.

---

## 📁 Folder Structure

Place everything in a single folder like this:

```
your_folder/
├── app_manager_windows_interactive.bat
└── installers/
    ├── python-3.12.2-amd64.exe
    ├── nssm-2.24.zip
    └── nginx-1.27.4.zip
```

> ✅ Make sure the `installers` folder is next to the `.bat` file.

---

## 🚀 How to Use

1. **Run the batch file as Administrator**

```cmd
Right click > Run as Administrator
```

2. **Choose from the menu**:

```
0) Setup server (install Python, nginx and NSSM from installers)
1) Setup nginx config + start nginx
2) Install app as service (NSSM)
3) Start app
4) Stop app
5) Restart app
6) View app status
7) View app logs
8) Uninstall app service
```

---

## 🔧 What Each Option Does

### 0) Setup Server
- Installs Python silently
- Creates virtual environment and installs `waitress`
- Extracts `nssm` and `nginx` from ZIP files

### 1) Setup nginx
- Configures nginx as a reverse proxy to `127.0.0.1:8000`
- Starts nginx using `nginx.exe`

### 2) Install Service
- Registers your Flask app as a **Windows service** using NSSM
- Ensures it runs on boot and stays alive after user logout

### 3–5) Control the Flask service
- Start, stop, or restart your app like a normal Windows service

### 6) Check Status
- Displays whether the app is running

### 7) View Logs
- Tails the stdout log (`out.log`) using PowerShell live output

### 8) Uninstall
- Removes the NSSM-based service cleanly

---

## 🔐 Security Notes

By default, the service runs as `Local System`. If you need domain access (e.g., to UNC shares or other AD resources), you can manually set the service account:

```cmd
nssm set AppName ObjectName "DOMAIN\youradmin" "YourPassword"
```

Make sure that user has **Log on as a service** rights (`secpol.msc`).

---

## 🧪 Test After Setup

Visit:
```
http://localhost
```

You should see your Flask app loaded via nginx reverse proxy.

---

## 🙌 Done!

Now you've got a 100% offline-capable deployment for Flask on Windows using Python, nginx, and NSSM — script-controlled, persistent, and production-ready.

