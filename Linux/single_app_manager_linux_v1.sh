#!/bin/bash

set -e

DOMAIN="domain.com"
APP_NAME="AppName"
PORT="8000"

EMAIL="admin@$DOMAIN"
APP_DIR="/home/ubuntu/$APP_NAME"
VENV_PATH="$APP_DIR/venv"
MODULE="source:create_app()"
NGINX_CONF="/etc/nginx/sites-available/$APP_NAME"
SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"

echo ""
echo "🔧 What do you want to do?"
echo "0) Bootstrap base system"
echo "1) Setup nginx + SSL"
echo "2) Start app"
echo "3) Stop app"
echo "4) Restart app"
echo "5) View app logs"
echo "6) Check app status"
read -p "Enter number [0-6]: " choice

echo ""

case $choice in

0)
    echo "🧱 Updating system and installing essentials..."
    sudo apt update && sudo apt upgrade -y

    echo "🌍 Setting timezone to Asia/Jerusalem..."
    sudo timedatectl set-timezone Asia/Jerusalem

    echo "🛠 Installing Python..."
    sudo apt install -y python3-pip python3-venv

    echo "✅ Base system setup complete. You may want to reboot now:"
    echo "   sudo reboot"
    ;;

1)
    echo "🔧 Installing nginx, UFW and required packages..."
    sudo apt install -y nginx certbot python3-certbot-nginx ufw

    echo "📄 Creating basic HTTP nginx config..."
    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx

    echo "🔐 Requesting SSL certificate with Certbot..."
    if ! sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"; then
        echo "⚠️ Certbot failed via nginx plugin. Trying standalone..."
        sudo systemctl stop nginx
        sudo certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
        sudo systemctl start nginx
    fi

    echo "🛡️ Configuring UFW..."
    sudo ufw allow 'Nginx Full'
    sudo ufw allow OpenSSH
    sudo ufw --force enable

    echo "🧪 Verifying HTTPS setup..."
    if curl -s --head https://$DOMAIN | grep -q "200 OK"; then
        echo "✅ HTTPS is working!"
    else
        echo "⚠️ HTTPS not responding. Check your app or firewall manually."
    fi

    echo "🎉 NGINX + SSL setup completed for $DOMAIN"
    ;;

2)
    echo "🔧 Creating systemd service for $APP_NAME..."

    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Gunicorn app for $APP_NAME
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_PATH/bin"
ExecStart=$VENV_PATH/bin/gunicorn -w 3 -b 127.0.0.1:$PORT $MODULE

[Install]
WantedBy=multi-user.target
EOF

    echo "🚀 Reloading systemd, enabling + starting $APP_NAME..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$APP_NAME"

    echo "📋 Status:"
    sudo systemctl status "$APP_NAME" --no-pager
    ;;

3)
    echo "🛑 Stopping and disabling $APP_NAME service..."
    sudo systemctl stop "$APP_NAME"
    sudo systemctl disable "$APP_NAME"

    echo "✅ $APP_NAME service stopped and disabled."
    ;;

4)
    echo "🔁 Restarting $APP_NAME service..."
    sudo systemctl restart "$APP_NAME"
    echo "✅ Restart complete."
    ;;

5)
    echo "📜 Tailing logs for $APP_NAME..."
    sudo journalctl -u "$APP_NAME" -f
    ;;

6)
    echo "🔍 Checking $APP_NAME status..."
    sudo systemctl status "$APP_NAME" --no-pager
    ;;

*)
    echo "❌ Invalid choice. Exiting."
    exit 1
    ;;
esac
