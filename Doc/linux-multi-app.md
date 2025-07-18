# 🐧 Linux Multi-App Manager: The Definitive Guide

This guide provides comprehensive instructions for using the `multi_app_manager_linux_v2.sh` script. This powerful tool is designed to deploy, manage, and host **multiple web applications** on a single Linux server (Debian/Ubuntu), including both Python-based apps and static HTML/CSS/JS sites.

This script acts as a central control panel for a multi-tenant environment, capable of handling complex deployment scenarios across various domains, subdomains, and even sub-paths.

**Target Script:** `Linux/multi_app_manager_linux_v2.sh`

---

## Table of Contents
1.  [✨ What This Script Does (Features)](#-what-this-script-does-features)
2.  [📦 Prerequisites](#-prerequisites)
3.  [⚙️ The Core Concept: The `ConfigureApplications` Registry](#️-the-core-concept-the-configureapplications-registry)
    *   [Parameter Breakdown](#parameter-breakdown)
    *   [Visual Example: From Config to Live URLs](#visual-example-from-config-to-live-urls)
4.  [🚀 Step-by-Step Installation & Deployment Guide](#-step-by-step-installation--deployment-guide)
5.  [📜 In-Depth Menu Guide](#-in-depth-menu-guide)
6.  [🛠️ Advanced Topics & FAQ](#️-advanced-topics--faq)
7.  [🔩 How It Works: A Technical Deep Dive](#-how-it-works-a-technical-deep-dive)

---

## ✨ What This Script Does (Features)

- **Server Preparation:** Automatically installs and configures Nginx, Python build tools, Certbot, UFW (firewall), and OpenSSL.
- **Multi-Tenant Hosting:** Manages any number of applications, each with its own deployment type.
- **Dynamic Nginx Configs:** Intelligently generates and updates Nginx configuration files, correctly handling primary domains and applications served from sub-paths.
- **Process Management:** Deploys each Python application as a separate, robust `systemd` service for reliability and auto-restarts on boot.
- **Python Environment Isolation:** Creates a dedicated Python virtual environment (`venv`) for each app to manage its dependencies independently.
- **Automated SSL:** Integrates with Let's Encrypt (Certbot) to obtain and configure SSL certificates, including support for wildcard certificates.
- **Lifecycle Management:** Provides a simple menu-driven interface to deploy, update, start, stop, view logs, and uninstall applications.
- **System Maintenance:** Includes tools to sync configurations and clean up orphaned files.

---

## 📦 Prerequisites

1.  **Server:** A fresh Debian or Ubuntu server.
2.  **User Account:** Run this script as a non-root user with `sudo` privileges (e.g., the default `ubuntu` user on an AWS EC2 instance).
3.  **DNS Configured:** Your domains and subdomains (`yourdomain.com`, `test.yourdomain.com`, etc.) must be pointed to your server's public IP address.
4.  **Application Code:** Have your Python application source code and a `requirements.txt` file ready to upload to the server.

---

## ⚙️ The Core Concept: The `ConfigureApplications` Registry

This is the heart of the script. All your applications are defined inside the `ConfigureApplications()` bash function. This centralized registry makes your entire server configuration readable, version-controllable, and easy to manage.

```bash
# In multi_app_manager_linux_v2.sh

function ConfigureApplications() {
    # Usage: RegisterApp "AppName" "DeployType" "Domain" "Port" "PythonModule" "Subpath"

    # --- A static landing page at the root domain ---
    RegisterApp "LandingPage" "STATIC"    "${ROOT_DOMAIN}"      ""      ""                  ""

    # --- A Python app on a subdomain ---
    RegisterApp "TestApp"    "SUBDOMAIN" "test.${ROOT_DOMAIN}" "8002"  "source:create_app()" ""

    # --- A Python app running under a subpath of the main domain ---
    RegisterApp "CS_Tool"    "SUBPATH"   "${ROOT_DOMAIN}"      "8003"  "admin_app:start" "/cs"
}
```

### Parameter Breakdown

| Parameter      | Description                                                                                                                                                                                             | Example                             |
| :------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :---------------------------------- |
| `AppName`      | A unique, descriptive name with no spaces. Used for folder names (`/srv/www/AppName`) and service names (`AppName.service`).                                                                              | `"LandingPage"`, `"TestApp"`        |
| `DeployType`   | The role of the application. Determines how Nginx and systemd are configured. See below.                                                                                                                | `"STATIC"`, `"SUBDOMAIN"`, `"SUBPATH"` |
| `Domain`       | The full domain or subdomain this app will respond to.                                                                                                                                                  | `"${ROOT_DOMAIN}"`, `"test.${ROOT_DOMAIN}"` |
| `Port`         | A **unique** local port for the Python app's Gunicorn process. Ignored for `STATIC` apps (use `""`).                                                                                                      | `"8002"`, `"8003"`                  |
| `PythonModule` | The Gunicorn callable in `module:callable` format. Ignored for `STATIC` apps (use `""`).                                                                                                                  | `"source:create_app()"`, `"admin_app:start"` |
| `Subpath`      | The URL path prefix. **Required only for `SUBPATH` type**, otherwise use `""`. Must start with a `/`.                                                                                                     | `"/cs"`                             |

**Deployment Types Explained:**
*   `ROOT`, `SUBDOMAIN`, `STATIC`: These are **primary** types. They "own" a domain's Nginx configuration file. There can only be **one** primary app per domain.
*   `SUBPATH`: This is a **secondary** type. It "borrows" a `location` block within the Nginx configuration of a primary app. You can have multiple `SUBPATH` apps on a single domain.

### Visual Example: From Config to Live URLs

Using the configuration example from above, here is what the script will create:

| AppName       | DeployType | Configured Domain | Configured Path | Resulting Live URL                          |
| :------------ | :--------- | :---------------- | :-------------- | :------------------------------------------ |
| `LandingPage` | `STATIC`   | `yourdomain.com`  | `""`            | `http://yourdomain.com/`                    |
| `TestApp`     | `SUBDOMAIN`| `test.yourdomain.com` | `""`          | `http://test.yourdomain.com/`               |
| `CS_Tool`     | `SUBPATH`  | `yourdomain.com`  | `"/cs"`         | `http://yourdomain.com/cs/`                 |

---

## 🚀 Step-by-Step Installation & Deployment Guide

Follow this workflow carefully for a smooth first-time setup.

#### Step 1: Prepare and Upload the Script
1.  Edit `multi_app_manager_linux_v2.sh` on your local machine.
2.  Set the `ROOT_DOMAIN` variable at the top.
3.  Fill out the `ConfigureApplications()` function with all the apps you plan to host.
4.  Upload the script to your server (e.g., to your home directory).
5.  Make it executable: `chmod +x multi_app_manager_linux_v2.sh`.

#### Step 2: Run the Script & Bootstrap the Server
1.  Start the script: `./multi_app_manager_linux_v2.sh`.
2.  From the main menu, select **Option 0) Bootstrap Server**.
3.  This one-time process installs Nginx, Python, Certbot, UFW, generates essential SSL parameters, and configures the firewall. It can take a few minutes.

#### Step 3: Initial Deployment of PRIMARY Apps
This step creates the necessary directories and service files.
1.  From the main menu, select **Option 1) Manage an Application**.
2.  Choose a **primary** app (`ROOT`, `SUBDOMAIN`, or `STATIC`).
3.  Select **"1) Deploy Application"**.
4.  Choose your desired SSL option. For a first test, `HTTP only` is fine.
5.  The script will now create the application's directory structure (e.g., `/srv/www/AppName/source`) and its `systemd` service file (if it's a Python app).
6.  **Repeat this for ALL your primary applications.** This ensures all Nginx config files and app directories are created.

#### Step 4: Upload Your Application Code
Now that the directories exist, you can upload your code.
1.  On your local machine, use `scp` or `git clone` to transfer your application source code into the corresponding `source` directory on the server.
    *   **Example:** For an app named `TestApp`, you would upload your code to `/srv/www/TestApp/source/`.
2.  Ensure your `requirements.txt` file is present in the application's main directory (e.g., `/srv/www/TestApp/requirements.txt`). The script checks here first.

#### Step 5: Finalize Deployment (Install Dependencies)
1.  Go back to the script's menu: **Option 1) Manage an Application**.
2.  Select the same app you just uploaded code for.
3.  Select **"6) Re-run Deployment"**.
4.  The script will now detect the `requirements.txt` file and install all your Python dependencies into the app's virtual environment.
5.  **Repeat for every Python application.**

#### Step 6: Deploy `SUBPATH` Applications
If you have any `SUBPATH` applications, deploy them now using the same process as in Step 3 & 4. The script will intelligently modify the existing Nginx config of the parent domain.

#### Step 7: Activate and Verify
1.  In the main menu, go to **Option 2) Manage Nginx Service** and select **"3) Reload Nginx Config"**. This applies all the new site configurations.
2.  Go to **Option 1) Manage an Application**, select a Python app, and choose **"1) Start Service"**.
3.  Repeat for all your Python apps.
4.  Visit your URLs in a browser to confirm everything is working!

---

## 📜 In-Depth Menu Guide

- **`0) Bootstrap Server`**: A critical first step. It installs Nginx, Python, Certbot, UFW, sets firewall rules for HTTP/HTTPS, and generates a `dhparam.pem` file for stronger SSL security.

- **`1) Manage an Application`**: Your main control panel for individual apps.
    - **`Start/Stop/Restart Service`**: Controls the `systemd` service for a Python app. The menu conveniently shows the live status (`active` or `inactive`).
    - **`View Service Status`**: Shows detailed output from `systemctl status`, including recent log entries, useful for quick debugging.
    - **`View App Logs (tail -f)`**: Streams the live logs from your application (`journalctl -u AppName.service -f`). Press `CTRL+C` to exit. This is the best way to see runtime errors.
    - **`Re-run Deployment`**: Use this to update your app. It will re-install packages from `requirements.txt` and regenerate config files.
    - **`View Nginx Config`**: Displays the contents of the Nginx configuration file for that app's domain.
    - **`Uninstall Application`**: A safe removal process. It stops and disables the service, removes the `systemd` file, and either removes the Nginx config (for primary apps) or instructs you to re-deploy the parent app (for subpath apps) to safely remove the `location` block.

- **`2) Manage Nginx Service`**:
    - **`Reload Nginx Config`**: The safe way to apply new configurations. It tests the config files first (`nginx -t`) and only reloads if there are no errors. Use this after deploying or uninstalling an app.
    - **`Test Nginx Configuration`**: Manually runs `nginx -t` to check for syntax errors in your config files.

- **`3) Manage SSL Certificates`**:
    - **`Renew All`**: Runs `certbot renew`. Let's Encrypt certificates are typically valid for 90 days.
    - **`Generate Wildcard`**: Starts the interactive process to get a `*.yourdomain.com` certificate. This requires you to manually create a DNS TXT record at your domain registrar.

- **`4) Sync and Clean Stale Nginx Configs`**: A housekeeping utility. It compares the apps in `ConfigureApplications` with the enabled Nginx sites and removes symlinks for apps you've commented out or deleted from the script config but didn't formally uninstall.

---

## 🛠️ Advanced Topics & FAQ

**Q: How do I update my application's code?**
A: 1. `cd /srv/www/AppName/source`
   2. Use `git pull` or `scp` to update the files.
   3. In the script menu, select the app and choose **"Restart Service"**.

**Q: How do I add or update Python dependencies?**
A: 1. Update the `requirements.txt` file in `/srv/www/AppName/`.
   2. In the script menu, select the app and choose **"Re-run Deployment"**. This will run `pip install -r requirements.txt` in the correct virtual environment.

**Q: Where are the important files located?**
*   **App Code:** `/srv/www/AppName/source/`
*   **Python venv:** `/srv/www/AppName/venv/`
*   **Nginx Configs (Available):** `/etc/nginx/sites-available/`
*   **Nginx Configs (Enabled):** `/etc/nginx/sites-enabled/` (These are symlinks)
*   **Systemd Services:** `/etc/systemd/system/AppName.service`
*   **SSL Certificates:** `/etc/letsencrypt/live/yourdomain.com/`

**Q: My service is "inactive (dead)". What do I do?**
A: This usually means your Python app crashed on startup.
   1. Select the app in the **Manage Application** menu.
   2. Choose **"View App Logs"**.
   3. Scroll through the logs to find the Python traceback or error message that caused the crash.

**Q: Nginx failed to reload. What's wrong?**
A: There's a syntax error in a config file.
   1. In the **Manage Nginx Service** menu, choose **"Test Nginx Configuration"**.
   2. Nginx will tell you exactly which file and line number has the error.
   3. Use the **"View Nginx Config"** option to examine the file. The error is often related to a mistyped domain or a missing semicolon.

---

## 🔩 How It Works: A Technical Deep Dive

- **Gunicorn & systemd:** For each Python app, the script creates a `systemd` service file that runs the app using `gunicorn`, a production-ready WSGI HTTP server. The service ensures the app starts on boot and can be managed like any other system process.
- **Nginx Reverse Proxy:** Nginx listens on the public ports (80 and 443). When a request comes in for a specific domain, Nginx proxies it internally to the correct Gunicorn process listening on its local port (e.g., `127.0.0.1:8002`). For static sites, Nginx serves the files directly from the filesystem.
- **Dynamic Config Generation:** The script's power comes from its ability to build Nginx configs. When you deploy a `SUBPATH` app, it doesn't create a new file. Instead, it finds the config for the parent domain, reads it, and generates a *new* version that includes the original `location /` block plus the new `location /subpath/` block, ensuring both routes work seamlessly.
- **Certbot & SSL:** For SSL, Nginx is configured to handle the `.well-known/acme-challenge` used by Certbot for domain validation. The script includes recommended SSL cipher suites and parameters from Certbot for A+ security ratings.