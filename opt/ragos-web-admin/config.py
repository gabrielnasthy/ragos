"""
RAGOS Web Admin - Configuration
================================
Configuration settings for the RAGOS Web Administration interface
"""

import os
import secrets

# Base directory
BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# Flask configuration
SECRET_KEY = os.environ.get('SECRET_KEY') or secrets.token_hex(32)
DEBUG = os.environ.get('DEBUG', 'False').lower() == 'true'
SESSION_COOKIE_SECURE = not DEBUG  # True in production
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = 'Lax'
SESSION_TYPE = 'filesystem'
PERMANENT_SESSION_LIFETIME = 1800  # 30 minutes

# Database configuration
DATABASE_PATH = os.path.join(BASE_DIR, 'database', 'ragos_web.db')

# AD/Samba configuration
AD_DOMAIN = os.environ.get('AD_DOMAIN', 'RAGOS.INTRA')
AD_REALM = os.environ.get('AD_REALM', 'RAGOS.INTRA')
AD_SERVER = os.environ.get('AD_SERVER', '10.0.3.1')
AD_BASE_DN = 'DC=RAGOS,DC=INTRA'

# Storage paths
NFS_MOUNT = os.environ.get('NFS_MOUNT', '/mnt/ragostorage')
QUOTA_FILESYSTEM = os.environ.get('QUOTA_FILESYSTEM', '/mnt/ragostorage')
NFS_HOME = os.path.join(NFS_MOUNT, 'nfs_home')

# Monitoring configuration
REFRESH_INTERVAL = 5000  # milliseconds
LOG_FILE = os.environ.get('LOG_FILE', '/var/log/ragos-web-admin.log')
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')

# Security settings
MAX_LOGIN_ATTEMPTS = 5
LOGIN_TIMEOUT = 300  # 5 minutes lockout

# Samba tool paths
SAMBA_TOOL = '/usr/bin/samba-tool'
SETQUOTA_CMD = '/usr/bin/setquota'
QUOTA_CMD = '/usr/bin/quota'
REPQUOTA_CMD = '/usr/bin/repquota'

# Quota defaults (in MB)
DEFAULT_SOFT_LIMIT = 5120   # 5 GB
DEFAULT_HARD_LIMIT = 10240  # 10 GB

# Application settings
APP_NAME = 'RAGOS Web Admin'
APP_VERSION = '1.0.0'
PAGINATION_PER_PAGE = 25

# Role definitions
ROLES = {
    'admin': ['user_create', 'user_delete', 'user_edit', 'group_manage', 'quota_manage', 'system_config'],
    'helpdesk': ['user_edit', 'user_reset_password', 'group_view', 'quota_view'],
    'user': ['view_own_info']
}
