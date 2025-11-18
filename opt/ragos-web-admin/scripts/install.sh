#!/bin/bash
# RAGOS Web Admin - Installation Script
# This script installs and configures the RAGOS Web Admin application

set -e

INSTALL_DIR="/opt/ragos-web-admin"
SERVICE_USER="ragos-admin"
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_FILE="/etc/systemd/system/ragos-web-admin.service"

echo "======================================"
echo "RAGOS Web Admin Installation"
echo "======================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

echo "[1/8] Creating service user..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
    echo "User $SERVICE_USER created"
else
    echo "User $SERVICE_USER already exists"
fi

echo ""
echo "[2/8] Setting up directory structure..."
mkdir -p "$INSTALL_DIR"/{database,flask_session,logs}
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"

echo ""
echo "[3/8] Creating Python virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    echo "Virtual environment created"
else
    echo "Virtual environment already exists"
fi

echo ""
echo "[4/8] Installing Python dependencies..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
echo "Dependencies installed"

echo ""
echo "[5/8] Initializing database..."
cd "$INSTALL_DIR"
if [ ! -f "$INSTALL_DIR/database/ragos_web.db" ]; then
    sudo -u "$SERVICE_USER" "$VENV_DIR/bin/python" -c "
import sys
sys.path.insert(0, '$INSTALL_DIR')
from app import init_db
init_db()
print('Database initialized')
"
else
    echo "Database already exists"
fi

echo ""
echo "[6/8] Setting permissions..."
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"
chmod 640 "$INSTALL_DIR/database/ragos_web.db"
chmod 750 "$INSTALL_DIR/logs"

# Allow ragos-admin user to run samba-tool and quota commands
echo "$SERVICE_USER ALL=(ALL) NOPASSWD: /usr/bin/samba-tool, /usr/bin/setquota, /usr/bin/quota, /usr/bin/repquota, /usr/bin/systemctl status *" > /etc/sudoers.d/ragos-admin
chmod 440 /etc/sudoers.d/ragos-admin

echo ""
echo "[7/8] Creating systemd service..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=RAGOS Web Admin Application
After=network.target samba.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin"
Environment="FLASK_APP=app.py"
Environment="PYTHONUNBUFFERED=1"
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/ragos-web-admin.log
StandardError=append:/var/log/ragos-web-admin.log

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR/database $INSTALL_DIR/flask_session $INSTALL_DIR/logs /var/log

[Install]
WantedBy=multi-user.target
EOF

# Create log file
touch /var/log/ragos-web-admin.log
chown "$SERVICE_USER":"$SERVICE_USER" /var/log/ragos-web-admin.log
chmod 640 /var/log/ragos-web-admin.log

echo ""
echo "[8/8] Enabling and starting service..."
systemctl daemon-reload
systemctl enable ragos-web-admin.service
systemctl start ragos-web-admin.service

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "Service Status:"
systemctl status ragos-web-admin.service --no-pager || true
echo ""
echo "Access the web interface at: http://localhost:5000"
echo "Default admin credentials: administrator / (your AD password)"
echo ""
echo "Logs: /var/log/ragos-web-admin.log"
echo "Database: $INSTALL_DIR/database/ragos_web.db"
echo ""
echo "To manage the service:"
echo "  Start:   systemctl start ragos-web-admin"
echo "  Stop:    systemctl stop ragos-web-admin"
echo "  Restart: systemctl restart ragos-web-admin"
echo "  Status:  systemctl status ragos-web-admin"
echo "  Logs:    journalctl -u ragos-web-admin -f"
echo ""
