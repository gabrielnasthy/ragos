# RAGOS Web Admin

A production-ready web application for centralized Active Directory management in the RAGOSthinclient infrastructure.

## Features

### User Management
- List, create, edit, and delete AD users
- Reset user passwords
- Enable/disable user accounts
- View user information and group memberships
- Real-time user quota monitoring

### Group Management
- List, create, and delete AD groups
- Add/remove group members
- View group memberships
- Protected system groups (Domain Admins, etc.)

### Quota Management
- Set and manage user disk quotas
- Pre-defined quota policies
- Real-time usage monitoring
- Visual usage indicators
- Top users by disk usage

### System Monitoring
- Real-time system metrics (CPU, Memory, Disk)
- Service status monitoring (Samba, NFS, etc.)
- Active session tracking
- Storage usage overview

### Reports & Audit
- Comprehensive audit logging
- User activity reports
- Storage usage analytics
- Administrative action tracking

## Technology Stack

- **Backend**: Flask 3.0 (Python)
- **Database**: SQLite3
- **Frontend**: Bootstrap 5, jQuery, DataTables, Chart.js
- **Authentication**: Kerberos/AD integration
- **Integration**: Samba-tool, Linux quota commands

## Installation

### Prerequisites

- Arch Linux with Samba AD DC configured
- Python 3.8 or higher
- Samba-tool and quota utilities installed
- Root/sudo access

### Quick Install

1. Copy the application to `/opt/ragos-web-admin/`
2. Run the installation script:
   ```bash
   cd /opt/ragos-web-admin
   chmod +x scripts/install.sh
   sudo ./scripts/install.sh
   ```

3. The installer will:
   - Create a service user (`ragos-admin`)
   - Set up Python virtual environment
   - Install dependencies
   - Initialize the database
   - Configure systemd service
   - Start the application

4. Access the web interface at: `http://your-server:5000`

### Manual Installation

```bash
# Create directory structure
mkdir -p /opt/ragos-web-admin/{database,flask_session,logs}

# Create virtual environment
python3 -m venv /opt/ragos-web-admin/venv

# Install dependencies
source /opt/ragos-web-admin/venv/bin/activate
pip install -r /opt/ragos-web-admin/requirements.txt

# Initialize database
cd /opt/ragos-web-admin
python app.py  # Will initialize database on first run

# Create systemd service (see scripts/install.sh for template)
```

## Configuration

Edit `/opt/ragos-web-admin/config.py` to customize:

```python
# AD Configuration
AD_DOMAIN = 'RAGOS.INTRA'
AD_REALM = 'RAGOS.INTRA'
AD_SERVER = '10.0.3.1'

# Storage Paths
NFS_MOUNT = '/mnt/ragostorage'
QUOTA_FILESYSTEM = '/mnt/ragostorage'

# Session Settings
PERMANENT_SESSION_LIFETIME = 1800  # 30 minutes

# Security
MAX_LOGIN_ATTEMPTS = 5
LOGIN_TIMEOUT = 300  # 5 minutes
```

Or use environment variables:
```bash
export AD_DOMAIN=RAGOS.INTRA
export AD_SERVER=10.0.3.1
export NFS_MOUNT=/mnt/ragostorage
export DEBUG=false
```

## Usage

### Service Management

```bash
# Start service
sudo systemctl start ragos-web-admin

# Stop service
sudo systemctl stop ragos-web-admin

# Restart service
sudo systemctl restart ragos-web-admin

# Check status
sudo systemctl status ragos-web-admin

# View logs
sudo journalctl -u ragos-web-admin -f
```

### Default Login

- **Username**: `administrator` (or any AD admin user)
- **Password**: Your Active Directory password

### User Roles

- **Admin**: Full access to all features (Domain Admins group members)
- **Helpdesk**: Limited access (password resets, view-only)
- **User**: View own information only

## Backup & Restore

### Create Backup

```bash
sudo /opt/ragos-web-admin/scripts/backup.sh
```

Backups are stored in: `/var/backups/ragos-web-admin/`

### Restore from Backup

```bash
# Stop service
sudo systemctl stop ragos-web-admin

# Extract backup
sudo tar -xzf /var/backups/ragos-web-admin/ragos-backup-TIMESTAMP.tar.gz -C /opt/ragos-web-admin

# Fix permissions
sudo chown -R ragos-admin:ragos-admin /opt/ragos-web-admin

# Start service
sudo systemctl start ragos-web-admin
```

## Security

### Authentication
- Kerberos-based AD authentication
- Session timeout (30 minutes default)
- Failed login attempt tracking
- Account lockout after 5 failed attempts

### Authorization
- Role-based access control (RBAC)
- Admin operations require Domain Admins membership
- Protected system accounts (administrator cannot be deleted/disabled)

### Data Protection
- CSRF protection on all forms
- Input validation and sanitization
- SQL injection prevention (parameterized queries)
- Command injection prevention (subprocess with argument lists)
- Secure session cookies (HttpOnly, SameSite)

### Audit Logging
- All administrative actions logged
- User, timestamp, action, target, and IP address recorded
- 30-day retention policy

## API Endpoints

### Authentication
- `POST /api/login` - Authenticate user
- `POST /api/logout` - Logout user

### Users
- `GET /api/users` - List all users
- `GET /api/users/<username>` - Get user details
- `POST /api/users` - Create user (admin)
- `DELETE /api/users/<username>` - Delete user (admin)
- `POST /api/users/<username>/enable` - Enable user (admin)
- `POST /api/users/<username>/disable` - Disable user (admin)
- `POST /api/users/<username>/reset-password` - Reset password (admin)

### Groups
- `GET /api/groups` - List all groups
- `GET /api/groups/<groupname>` - Get group details
- `POST /api/groups` - Create group (admin)
- `DELETE /api/groups/<groupname>` - Delete group (admin)
- `POST /api/groups/<groupname>/members` - Add members (admin)
- `DELETE /api/groups/<groupname>/members/<username>` - Remove member (admin)

### Quotas
- `GET /api/quotas` - List all quotas
- `GET /api/quotas/<username>` - Get user quota
- `POST /api/quotas/<username>` - Set quota (admin)
- `GET /api/quota-policies` - List quota policies

### Monitoring
- `GET /api/monitoring/system` - System metrics
- `GET /api/monitoring/services` - Service status
- `GET /api/monitoring/storage` - Storage usage
- `GET /api/monitoring/sessions` - Active sessions (admin)
- `GET /api/monitoring/audit-log` - Audit log (admin)

## Troubleshooting

### Service won't start
```bash
# Check logs
sudo journalctl -u ragos-web-admin -n 50

# Check permissions
ls -la /opt/ragos-web-admin/database/

# Test manually
sudo -u ragos-admin /opt/ragos-web-admin/venv/bin/python /opt/ragos-web-admin/app.py
```

### Can't login
- Verify AD is running: `sudo systemctl status samba`
- Test AD authentication: `kinit administrator@RAGOS.INTRA`
- Check user exists: `samba-tool user list`
- Review login attempts: Check audit log in database

### Quota commands fail
- Verify quotas enabled on filesystem: `mount | grep quota`
- Check quota tools installed: `which setquota quota repquota`
- Verify sudoers configuration: `/etc/sudoers.d/ragos-admin`

### Database errors
- Check database file exists and is writable
- Verify ownership: `sudo chown ragos-admin:ragos-admin /opt/ragos-web-admin/database/ragos_web.db`
- Reinitialize if corrupt: Delete database file and restart service

## Development

### Running in Debug Mode

```bash
export DEBUG=true
export FLASK_ENV=development
python app.py
```

### File Structure

```
/opt/ragos-web-admin/
├── app.py                 # Main Flask application
├── config.py             # Configuration
├── requirements.txt      # Python dependencies
├── database/
│   ├── schema.sql        # Database schema
│   └── ragos_web.db      # SQLite database
├── static/
│   ├── css/
│   │   └── custom.css    # Custom styles
│   ├── js/
│   │   ├── dashboard.js  # Dashboard logic
│   │   ├── users.js      # User management
│   │   ├── quotas.js     # Quota management
│   │   └── monitoring.js # Monitoring
│   └── vendors/          # Third-party libraries
├── templates/
│   ├── base.html        # Base template
│   ├── login.html       # Login page
│   ├── dashboard.html   # Dashboard
│   ├── users/           # User templates
│   ├── groups/          # Group templates
│   ├── quotas/          # Quota templates
│   ├── monitoring/      # Monitoring templates
│   └── reports/         # Report templates
├── utils/
│   ├── samba_manager.py # Samba integration
│   ├── quota_engine.py  # Quota management
│   └── ad_integration.py # AD authentication
└── scripts/
    ├── install.sh       # Installation script
    └── backup.sh        # Backup script
```

## Support

For issues, questions, or contributions, please refer to the RAGOSthinclient repository.

## License

This application is part of the RAGOSthinclient project.

## Version

Version 1.0.0
