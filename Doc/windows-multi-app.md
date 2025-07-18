# 💻 Windows Multi-App Manager: The Definitive Guide

This guide provides comprehensive instructions for using the `multi_app_manager_windows_v5.bat` script. This advanced tool is designed to deploy, manage, and host **multiple web applications** on a single Windows Server, including both Python-based apps and static HTML/CSS/JS sites.

This script is your central control panel for a multi-tenant environment, capable of handling complex deployment scenarios across various domains, subdomains, and even sub-paths.

**Target Script:** `Windows/multi_app_manager_windows_v5.bat`

---

## Table of Contents
1.  [✨ What This Script Does (Features)](#-what-this-script-does-features)
2.  [📦 Critical Prerequisite: The `installers` Folder](#-critical-prerequisite-the-installers-folder)
3.  [⚙️ The Core Concept: The `:ConfigureApplications` Registry](#️-the-core-concept-the-configureapplications-registry)
    *   [Parameter Breakdown](#parameter-breakdown)
    *   [Visual Example: From Config to Live URLs](#visual-example-from-config-to-live-urls)
4.  [🚀 Step-by-Step Installation & Deployment Guide](#-step-by-step-installation--deployment-guide)
5.  [📜 In-Depth Menu Guide](#-in-depth-menu-guide)
6.  [🛠️ Advanced Topics & FAQ](#️-advanced-topics--faq)
7.  [🔩 How It Works: A Technical Deep Dive](#-how-it-works-a-technical-deep-dive)

---

## ✨ What This Script Does (Features)

- **Automated Server Bootstrap:** Installs Python, Nginx, NSSM (service manager), OpenSSL, and Certbot directly from a local `installers` folder.
- **Windows Service Integration:** Deploys each Python application as a robust, auto-starting Windows Service using NSSM, ensuring reliability and proper process management.
- **Dynamic Nginx Configs:** Intelligently generates and updates Nginx configuration files, correctly handling primary domains and applications served from sub-paths.
- **Python Environment Isolation:** Creates a dedicated Python virtual environment (`venv`) for each app to manage its dependencies independently.
- **Automated SSL:** Integrates with Let's Encrypt (Certbot) to obtain, configure, and renew SSL certificates, including support for wildcard certificates.
- **Lifecycle Management:** Provides a simple menu-driven interface to deploy, update, start, stop, view logs, and uninstall applications.
- **System Maintenance:** Includes tools to sync configurations, clean up orphaned files, and manage the Windows Firewall.

---

## 📦 Critical Prerequisite: The `installers` Folder

This is the most important step for a successful setup. The script **requires** a specific folder structure to perform its initial bootstrap.

1.  **Create an `installers` folder** in the same directory as the `.bat` script.
2.  **Download and place ALL of the following files** into that folder:
    *   **Python:** The latest `amd64.exe` installer (e.g., `python-3.12.3-amd64.exe`).
    *   **Nginx:** The latest mainline version `.zip` file (e.g., `nginx-1.27.4.zip`).
    *   **NSSM:** The latest release `.zip` file (e.g., `nssm-2.24.zip`).
    *   **OpenSSL:** The "Win64 OpenSSL Light" `.exe` installer (e.g., `Win64OpenSSL_Light-3_x_x.exe`). This is required for generating SSL parameters.

Your folder structure **must** look like this:

```
your_project_folder/
├── multi_app_manager_windows_v5.bat
└── installers/
    ├── Win64OpenSSL_Light-3_5_1.exe
    ├── nginx-1.27.4.zip
    ├── nssm-2.24.zip
    └── python-3.12.3-amd64.exe
```

---

## ⚙️ The Core Concept: The `:ConfigureApplications` Registry

This is the heart of the script. All your applications are defined inside the `:ConfigureApplications` block. This centralized registry makes your entire server configuration readable, version-controllable, and easy to manage.

```batch
:: In multi_app_manager_windows_v5.bat

:ConfigureApplications
    set "APP_COUNT=0"
    :: Usage: call :RegisterApp "AppName" "DeployType" "Domain" "Port" "PythonModule" "Subpath"

    :: --- A static landing page at the root domain ---
    call :RegisterApp "LandingPage" "STATIC"    "%ROOT_DOMAIN%"         ""      ""                  ""

    :: --- A Python app on a subdomain ---
    call :RegisterApp "TestApp"    "SUBDOMAIN" "test.%ROOT_DOMAIN%"    "8002"  "source:create_app" ""

    :: --- A Python app running under a subpath of the main domain ---
    call :RegisterApp "CS_Tool"    "SUBPATH"   "%ROOT_DOMAIN%"         "8003"  "admin_app:start"   "/cs"

    goto :eof
```

### Parameter Breakdown

| Parameter      | Description                                                                                                                                                                                             | Example                             |
| :------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :---------------------------------- |
| `AppName`      | A unique, descriptive name with no spaces. Used for folder names (`C:\www\AppName`) and Windows Service names (`AppName_App_Service`).                                                                  | `"LandingPage"`, `"TestApp"`        |
| `DeployType`   | The role of the application. Determines how Nginx and NSSM are configured. See below.                                                                                                                   | `"STATIC"`, `"SUBDOMAIN"`, `"SUBPATH"` |
| `Domain`       | The full domain or subdomain this app will respond to.                                                                                                                                                  | `"%ROOT_DOMAIN%"`, `"test.%ROOT_DOMAIN%"` |
| `Port`         | A **unique** local port for the Python app's Waitress process. Ignored for `STATIC` apps (use `""`).                                                                                                      | `"8002"`, `"8003"`                  |
| `PythonModule` | The Waitress callable in `module:callable` format. Ignored for `STATIC` apps (use `""`).                                                                                                                  | `"source:create_app"`, `"admin_app:start"` |
| `Subpath`      | The URL path prefix. **Required only for `SUBPATH` type**, otherwise use `""`. Must start with a `/`.                                                                                                     | `"/cs"`                             |

**Deployment Types Explained:**
*   `ROOT`, `SUBDOMAIN`, `STATIC`: These are **primary** types. They "own" a domain's Nginx configuration file (`.conf`). There can only be **one** primary app per domain.
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

#### Step 1: Prepare the Script
1.  Edit `multi_app_manager_windows_v5.bat` on your local machine.
2.  Set the `ROOT_DOMAIN` variable at the top.
3.  Fill out the `:ConfigureApplications` block with all the apps you plan to host.

#### Step 2: Run the Script & Bootstrap the Server
1.  **Right-click `multi_app_manager_windows_v5.bat` and select "Run as administrator".**
2.  From the main menu, select **Option 0) Bootstrap Server**.
3.  This one-time process installs everything from your `installers` folder, sets up Nginx, and configures the firewall.
4.  ⚠️ **ACTION REQUIRED:** After bootstrap completes, the script may say `Python installed. CLOSE this terminal and RE-RUN the script.` **This is important!** You must close the command prompt and re-launch the script (as administrator) for the system's `PATH` variable to be updated correctly.

#### Step 3: Initial Deployment of PRIMARY Apps
This step creates the necessary directories and service definitions.
1.  From the main menu, select **Option 1) Manage an Application**.
2.  Choose a **primary** app (`ROOT`, `SUBDOMAIN`, or `STATIC`).
3.  Select **"1) Deploy Application"**.
4.  Choose your desired SSL option. For a first test, `HTTP only` is fine.
5.  The script will now create the application's directory structure (e.g., `C:\www\AppName\source`) and register its Windows Service with NSSM.
6.  **Repeat this for ALL your primary applications.**

#### Step 4: Upload Your Application Code
Now that the directories exist, you can upload your code.
1.  Use RDP File Explorer, FTP, or `git clone` to transfer your application source code into the corresponding directory on the server.
    *   **Example:** For an app named `TestApp`, you would upload your code to `C:\www\TestApp\`.
2.  Ensure your `requirements.txt` file is present in the application's main directory (e.g., `C:\www\TestApp\requirements.txt`).

#### Step 5: Finalize Deployment (Install Dependencies)
1.  Go back to the script's menu: **Option 1) Manage an Application**.
2.  Select the same app you just uploaded code for.
3.  Select **"6) Re-run Deployment"**.
4.  The script will now detect `requirements.txt` and install all your Python dependencies into the app's virtual environment.
5.  **Repeat for every Python application.**

#### Step 6: Deploy `SUBPATH` Applications
If you have any `SUBPATH` applications, deploy them now using the same process as in Step 3 & 4. The script will intelligently modify the existing Nginx config of the parent domain.

#### Step 7: Activate and Verify
1.  In the main menu, go to **Option 2) Manage Nginx Service** and select **"3) Reload Nginx Config"**. This tests and restarts Nginx to apply all new site configurations.
2.  Go to **Option 1) Manage an Application**, select a Python app, and choose **"1) Start Service"**.
3.  Repeat for all your Python apps.
4.  Visit your URLs in a browser to confirm everything is working!

---

## 📜 In-Depth Menu Guide

- **`0) Bootstrap Server`**: A critical first step. Installs all required software, configures Nginx, creates a firewall rule, and generates the `ssl-dhparams.pem` file.

- **`1) Manage an Application`**: Your main control panel for individual apps.
    - **`Start/Stop/Restart Service`**: Controls the app's Windows Service via NSSM.
    - **`View Service Status`**: Shows detailed output from `nssm status`.
    - **`View App Logs`**: Streams the live log file (`C:\www\AppName\logs\app.log`) using PowerShell. Press `CTRL+C` to exit. This is the best way to see runtime errors from your app.
    - **`Re-run Deployment`**: Use this to update your app. It will re-install packages from `requirements.txt` and regenerate config files.
    - **`View Nginx Config`**: Displays the contents of the Nginx configuration file for that app's domain.
    - **`Uninstall Application`**: A safe removal process. It stops and removes the Windows Service and either deletes the Nginx config (for primary apps) or instructs you to re-deploy the parent app (for subpath apps) to safely remove its routing.

- **`2) Manage Nginx Service`**:
    - **`Reload Nginx Config`**: The safe way to apply changes. It tests the config first (`nginx -t`) and only restarts the service if there are no errors.
    - **`Test Nginx Configuration`**: Manually runs `nginx -t` to check for syntax errors.

- **`3) Manage SSL Certificates`**:
    - **`Renew All`**: Runs `certbot renew`.
    - **`Generate Wildcard`**: Starts the interactive process to get a `*.yourdomain.com` certificate. This requires you to manually create a DNS TXT record at your domain registrar.

- **`4) Sync and Clean Stale Nginx Configs`**: A housekeeping utility. It removes Nginx `.conf` files for apps you've commented out or deleted from the script's configuration.

---

## 🛠️ Advanced Topics & FAQ

**Q: How do I update my application's code?**
A: 1. Update the files in `C:\www\AppName\`.
   2. In the script menu, select the app and choose **"3) Restart Service"**.

**Q: How do I add or update Python dependencies?**
A: 1. Update the `requirements.txt` file in `C:\www\AppName\`.
   2. In the script menu, select the app and choose **"6) Re-run Deployment"**. This will run `pip install -r requirements.txt` in the correct venv.

**Q: Where are the important files located?**
*   **App Code & Logs:** `C:\www\AppName\`
*   **Python venv:** `C:\www\AppName\venv\`
*   **Nginx Installation:** `C:\nginx\`
*   **Nginx Site Configs:** `C:\nginx\servers\`
*   **NSSM Installation:** `C:\nssm\`
*   **Certbot & SSL Files:** `C:\Certbot\`

**Q: My service won't start, or stops immediately. What do I do?**
A: This usually means your Python app crashed.
   1. Select the app in the **Manage Application** menu.
   2. Choose **"5) View App Logs"**.
   3. The `app.log` file will contain the Python traceback or error message.

**Q: Nginx failed to reload. What's wrong?**
A: There's a syntax error in a config file.
   1. In the **Manage Nginx Service** menu, choose **"4) Test Nginx Configuration"**.
   2. Nginx will tell you which file and line number has the error.
   3. Use the **"View Nginx Config"** option to examine the file.

---

## 🔩 How It Works: A Technical Deep Dive

- **Waitress & NSSM:** For each Python app, the script uses **Waitress**, a production-ready WSGI server for Windows. It then uses the **Non-Sucking Service Manager (NSSM)** to wrap the Waitress process into a proper Windows Service. This ensures the app starts on boot, can be managed via the Services panel, and has its output redirected to log files.
- **Nginx Reverse Proxy:** Nginx listens on the public ports (80 and 443). When a request comes in, Nginx proxies it internally to the correct Waitress process listening on its local port (e.g., `127.0.0.1:8002`). For static sites, Nginx serves the files directly.
- **Dynamic Config Generation:** The script's power comes from its ability to build Nginx configs. When you deploy a `SUBPATH` app, it doesn't create a new file. Instead, it finds the config for the parent domain and generates a *new* version that includes the original `location /` block plus the new `location /subpath/` block.
- **Certbot & SSL:** The script generates an `options-ssl-nginx.conf` and `ssl-dhparams.pem` file, which are included in the Nginx SSL server blocks to provide modern, strong encryption (TLS 1.2/1.3) and ciphers.