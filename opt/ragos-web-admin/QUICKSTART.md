# RAGOS Web Admin - Quick Start Guide

## Deployment Instructions

### 1. Copy Files to Target Server

```bash
# On your development/repository machine
cd /home/runner/work/ragos/ragos
sudo cp -r opt/ragos-web-admin /opt/

# Or if deploying to remote server
rsync -av opt/ragos-web-admin/ user@server:/opt/ragos-web-admin/
```

### 2. Run Installation Script

```bash
# On the RAGOS server
cd /opt/ragos-web-admin
sudo chmod +x scripts/install.sh
sudo ./scripts/install.sh
```

The installation will:
- Create a service user (ragos-admin)
- Install Python dependencies
- Initialize the database
- Configure systemd service
- Start the application

### 3. Access the Application

Open your web browser and navigate to:
```
http://your-server-ip:5000
```

Login with your Active Directory credentials:
- **Username**: `administrator` (or any Domain Admin user)
- **Password**: Your AD password

### 4. Configure Firewall (if needed)

```bash
# Allow port 5000
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --reload

# Or if using iptables
sudo iptables -I INPUT -p tcp --dport 5000 -j ACCEPT
sudo iptables-save > /etc/iptables/iptables.rules
```

### 5. Set Up Reverse Proxy (Production)

For production use, set up nginx as a reverse proxy:

```bash
# Install nginx
sudo pacman -S nginx

# Create nginx configuration
sudo nano /etc/nginx/sites-available/ragos-admin
```

Add this configuration:

```nginx
server {
    listen 80;
    server_name ragos-admin.ragos.intra;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable and restart nginx:

```bash
sudo ln -s /etc/nginx/sites-available/ragos-admin /etc/nginx/sites-enabled/
sudo systemctl enable nginx
sudo systemctl restart nginx
```

### 6. Configure SSL/TLS (Recommended)

```bash
# Install certbot
sudo pacman -S certbot certbot-nginx

# Get certificate
sudo certbot --nginx -d ragos-admin.ragos.intra
```

## Service Management

```bash
# Check status
sudo systemctl status ragos-web-admin

# View logs
sudo journalctl -u ragos-web-admin -f

# Restart service
sudo systemctl restart ragos-web-admin

# Stop service
sudo systemctl stop ragos-web-admin

# Start service
sudo systemctl start ragos-web-admin
```

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo journalctl -u ragos-web-admin -n 100 --no-pager

# Test manually
sudo -u ragos-admin /opt/ragos-web-admin/venv/bin/python /opt/ragos-web-admin/app.py
```

### Can't login

1. Verify Samba is running:
   ```bash
   sudo systemctl status samba
   ```

2. Test Kerberos authentication:
   ```bash
   kinit administrator@RAGOS.INTRA
   klist
   kdestroy
   ```

3. Check user exists:
   ```bash
   samba-tool user list | grep administrator
   ```

### Permission errors

```bash
# Fix ownership
sudo chown -R ragos-admin:ragos-admin /opt/ragos-web-admin

# Fix permissions
sudo chmod 750 /opt/ragos-web-admin
sudo chmod 640 /opt/ragos-web-admin/database/ragos_web.db
```

### Database issues

```bash
# Backup current database
sudo cp /opt/ragos-web-admin/database/ragos_web.db /tmp/ragos_web.db.backup

# Reinitialize database
sudo rm /opt/ragos-web-admin/database/ragos_web.db
sudo systemctl restart ragos-web-admin
```

## Backup & Restore

### Create Backup

```bash
# Manual backup
sudo /opt/ragos-web-admin/scripts/backup.sh

# Automated backup (add to crontab)
sudo crontab -e
# Add this line:
0 2 * * * /opt/ragos-web-admin/scripts/backup.sh
```

### Restore from Backup

```bash
# Stop service
sudo systemctl stop ragos-web-admin

# Restore database
sudo cp /var/backups/ragos-web-admin/ragos_web-TIMESTAMP.db \
       /opt/ragos-web-admin/database/ragos_web.db

# Fix permissions
sudo chown ragos-admin:ragos-admin /opt/ragos-web-admin/database/ragos_web.db

# Start service
sudo systemctl start ragos-web-admin
```

## Configuration

Edit `/opt/ragos-web-admin/config.py` to customize:

```python
# AD Settings
AD_DOMAIN = 'RAGOS.INTRA'
AD_SERVER = '10.0.3.1'

# Storage
QUOTA_FILESYSTEM = '/mnt/ragostorage'

# Security
SESSION_TIMEOUT = 1800  # 30 minutes
MAX_LOGIN_ATTEMPTS = 5
```

Or use environment variables:

```bash
# Create environment file
sudo nano /etc/ragos-web-admin.env
```

Add:
```bash
AD_DOMAIN=RAGOS.INTRA
AD_SERVER=10.0.3.1
QUOTA_FILESYSTEM=/mnt/ragostorage
DEBUG=false
```

Update systemd service:
```bash
sudo nano /etc/systemd/system/ragos-web-admin.service
```

Add under `[Service]`:
```
EnvironmentFile=/etc/ragos-web-admin.env
```

Restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart ragos-web-admin
```

## First-Time Setup

### 1. Login as Administrator

Use your AD administrator account.

### 2. Create Users

1. Go to **Users** menu
2. Click **Create User**
3. Fill in details:
   - Username (required)
   - Password (required, min 8 chars)
   - First/Last name
   - Email
4. Click **Create User**

### 3. Set Quotas

1. Go to **Quotas** menu
2. Click **Set Quota**
3. Select user
4. Set soft/hard limits (in MB)
5. Or select a pre-defined policy
6. Click **Set Quota**

### 4. Create Groups

1. Go to **Groups** menu
2. Click **Create Group**
3. Enter group name and description
4. Click **Create Group**
5. Click **Members** to add users

### 5. Monitor System

1. Go to **Monitoring** menu
2. View real-time system metrics
3. Check service status
4. Monitor storage usage

### 6. Review Audit Logs (Admin only)

1. Go to **Reports** menu
2. View audit log
3. Filter by user, action, date
4. Export if needed

## Security Best Practices

1. **Change Default Ports**
   - Don't expose port 5000 directly
   - Use reverse proxy with SSL

2. **Regular Backups**
   - Automate daily backups
   - Test restore procedures
   - Keep backups off-site

3. **Monitor Logs**
   - Review audit logs weekly
   - Set up log rotation
   - Watch for failed login attempts

4. **Update Regularly**
   - Keep dependencies updated
   - Apply security patches
   - Test updates in staging first

5. **Limit Access**
   - Use firewall rules
   - Implement IP whitelisting if needed
   - Use VPN for remote access

6. **Strong Passwords**
   - Enforce password complexity
   - Regular password rotation
   - Use 2FA if available

## Integration with RAGOS Infrastructure

This web application integrates with:

1. **Samba AD DC** - User and group management
2. **Linux Quotas** - Disk quota enforcement
3. **NFS Server** - Shared storage monitoring
4. **System Services** - Service status monitoring

Ensure all these services are running before starting the web admin.

## Support

For issues or questions:
1. Check the main README.md
2. Review logs: `journalctl -u ragos-web-admin`
3. Consult RAGOSthinclient documentation
4. Check GitHub repository issues

## Next Steps

After installation:

1. ✅ Verify all services are running
2. ✅ Create your first test user
3. ✅ Set up quotas for users
4. ✅ Configure automated backups
5. ✅ Set up SSL/TLS for production
6. ✅ Train administrators
7. ✅ Document local customizations

---

**Version**: 1.0.0  
**Last Updated**: 2024
