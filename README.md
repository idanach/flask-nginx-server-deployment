Of course! Here is a completely revamped `README.md` file.

This new version uses more engaging language, emojis, and a clear, visually appealing structure to guide users to the right solution quickly. It's designed to be more "eye-catching" and user-friendly, turning a simple file list into a compelling entry point for the project.

---

# 🚀 Launchpad: Automated Web App Deployment Scripts

[//]: # (<p align="center">)

[//]: # (  <img src="https://i.imgur.com/u4g5jT5.png" alt="Project Banner" width="700"/>)

[//]: # (</p>)

Welcome to **Launchpad**! This project provides a collection of powerful, menu-driven scripts that transform the complex task of deploying web applications into a simple, automated process.

Whether you're deploying a single Flask/Django app or managing a multi-tenant server, these tools handle the heavy lifting: web server setup (Nginx), process management (systemd/NSSM), application serving (Gunicorn/Waitress), and SSL certificate automation (Certbot).

Stop wrestling with manual configurations and start launching your apps in minutes.

---

## ✨ Core Features

| Feature                       | Windows 🦇                                                                    | Linux 🐧                                                                   |
| :---------------------------- | :---------------------------------------------------------------------------- | :------------------------------------------------------------------------- |
| **🤖 Automated Bootstrap**      | Installs Nginx, Python, NSSM, Certbot & OpenSSL from a local `installers` folder. | Installs Nginx, Python, Certbot & UFW using the `apt` package manager.       |
| **🛡️ Robust Service Management** | Deploys apps as reliable, auto-starting Windows Services using **NSSM**.      | Deploys apps as robust, auto-starting daemons using **systemd**.           |
| **🔄 Nginx Reverse Proxy**      | Automatically configures Nginx to serve your apps on HTTP and HTTPS.          | Automatically configures Nginx to serve your apps on HTTP and HTTPS.       |
| **🔒 SSL Automation**            | Integrates with **Let's Encrypt (Certbot)** for SSL certificate management.   | Integrates with **Let's Encrypt (Certbot)** for SSL certificate management. |
| **🏠 Single & Multi-App**       | Scripts available for both simple single-site and complex multi-tenant hosting. | Scripts available for both simple single-site and complex multi-tenant hosting. |
| **🎛️ Interactive UI**          | Simple, clear command-line menus for all actions.                             | Simple, clear command-line menus for all actions.                          |

---

## 🤔 Which Launchpad Script is Right for You?

Find your use case below and jump straight to the guide you need.

<br/>

### 🖥️ **I am deploying on a WINDOWS Server...**

<details>
<summary><strong>Scenario 1: I need to host ONE application.</strong></summary>
<br/>

> You have a single web application and need a simple, dedicated setup for one domain. This script is streamlined for getting one site online quickly and reliably.
>
> ### ➡️ **[Read the Windows Single-App Guide](./Doc/windows-single-app.md)**

</details>

<details>
<summary><strong>Scenario 2: I need to host MULTIPLE applications.</strong></summary>
<br/>

> You're building a multi-tenant server to host several apps on different domains, subdomains, or even different paths of the same domain (e.g., `domain.com`, `api.domain.com`, `domain.com/admin-tool`). This is the powerhouse script for maximum flexibility.
>
> ### ➡️ **[Read the Windows Multi-App Guide](./Doc/windows-multi-app.md)**

</details>

<br/>

### 🐧 **I am deploying on a LINUX Server (Debian/Ubuntu)...**

<details>
<summary><strong>Scenario 1: I need to host ONE application.</strong></summary>
<br/>

> You need a straightforward, rock-solid setup for a single domain on a Linux environment. This script automates the standard Gunicorn + Nginx + systemd stack.
>
> ### ➡️ **[Read the Linux Single-App Guide](./Doc/linux-single-app.md)**

</details>

<details>
<summary><strong>Scenario 2: I need to host MULTIPLE applications.</strong></summary>
<br/>

> You need a flexible system to manage multiple Python apps and static sites on various domains, subdomains, and sub-paths. This script turns your Linux server into a versatile hosting platform.
>
> ### ➡️ **[Read the Linux Multi-App Guide](./Doc/linux-multi-app.md)**

</details>

---

## 📂 Project Structure

Everything is organized by operating system and complexity.

```
.
├── Doc/                  <-- 📖 Detailed documentation for each script
├── Linux/                <-- 🐧 Scripts for Debian/Ubuntu-based systems
│   ├── single_app_manager_linux_v1.sh
│   └── multi_app_manager_linux_v2.sh
└── Windows/              <-- 🖥️ Scripts for Windows Server
    ├── installers/       <-- 📦 (CRITICAL) Required .exe/.zip installers go here!
    ├── single_app_manager_windows_v1.bat
    └── multi_app_manager_windows_v5.bat
```

## 🛑 General Prerequisites

- **Administrator / Sudo Access:** All scripts require elevated privileges to install software and manage services. They will attempt to self-elevate if not run correctly.
- **Application Code Ready:** Have your Python web application's source code and `requirements.txt` file ready for deployment.
- **(Windows Only)**: Before you begin, you **must** download and place the required installers (Python, Nginx, NSSM, OpenSSL) into the `Windows/installers` folder. This is a critical first step!

## License

This project is licensed under the MIT License. See the [LICENSE.md](LICENSE.md) file for details.