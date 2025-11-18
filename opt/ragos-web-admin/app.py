"""
RAGOS Web Admin - Main Application
====================================
Flask web application for centralized Active Directory management
"""

import os
import sys
import sqlite3
import logging
import json
import subprocess
from datetime import datetime, timedelta
from functools import wraps
from flask import Flask, render_template, request, jsonify, session, redirect, url_for, flash
from flask_session import Session
import psutil

# Add utils to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from utils import SambaManager, QuotaEngine, ADIntegration
from utils import SambaManagerException, QuotaException, ADAuthException
import config

# Initialize Flask app
app = Flask(__name__)
app.config.from_object(config)

# Configure session
app.config['SESSION_TYPE'] = 'filesystem'
app.config['SESSION_FILE_DIR'] = os.path.join(config.BASE_DIR, 'flask_session')
os.makedirs(app.config['SESSION_FILE_DIR'], exist_ok=True)
Session(app)

# Configure logging
logging.basicConfig(
    level=getattr(logging, config.LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(config.LOG_FILE) if os.access(os.path.dirname(config.LOG_FILE), os.W_OK) else logging.StreamHandler(),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Initialize managers
samba_manager = SambaManager(config.SAMBA_TOOL)
quota_engine = QuotaEngine(config.QUOTA_FILESYSTEM, config.SETQUOTA_CMD, config.QUOTA_CMD, config.REPQUOTA_CMD)
ad_integration = ADIntegration(config.AD_DOMAIN, config.AD_REALM, config.AD_SERVER)


# ========== DATABASE FUNCTIONS ==========

def get_db():
    """Get database connection"""
    conn = sqlite3.connect(config.DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Initialize database with schema"""
    try:
        os.makedirs(os.path.dirname(config.DATABASE_PATH), exist_ok=True)
        
        conn = get_db()
        with open(os.path.join(config.BASE_DIR, 'database', 'schema.sql'), 'r') as f:
            conn.executescript(f.read())
        conn.commit()
        conn.close()
        
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        raise


def log_audit(username, action, target=None, details=None, status='success'):
    """Log administrative action to audit log"""
    try:
        conn = get_db()
        ip_address = request.remote_addr if request else None
        
        conn.execute(
            'INSERT INTO audit_log (username, action, target, details, ip_address, status) VALUES (?, ?, ?, ?, ?, ?)',
            (username, action, target, json.dumps(details) if details else None, ip_address, status)
        )
        conn.commit()
        conn.close()
        
        logger.info(f"Audit log: {username} - {action} - {target}")
    except Exception as e:
        logger.error(f"Failed to log audit: {e}")


def check_login_attempts(username, ip_address):
    """Check if user has exceeded login attempts"""
    try:
        conn = get_db()
        
        # Count failed attempts in last 5 minutes
        threshold_time = datetime.now() - timedelta(minutes=5)
        
        cursor = conn.execute(
            'SELECT COUNT(*) FROM login_attempts WHERE username = ? AND success = 0 AND timestamp > ?',
            (username, threshold_time)
        )
        
        failed_count = cursor.fetchone()[0]
        conn.close()
        
        return failed_count < config.MAX_LOGIN_ATTEMPTS
        
    except Exception as e:
        logger.error(f"Failed to check login attempts: {e}")
        return True  # Allow login on error


def record_login_attempt(username, ip_address, success):
    """Record login attempt"""
    try:
        conn = get_db()
        conn.execute(
            'INSERT INTO login_attempts (username, ip_address, success) VALUES (?, ?, ?)',
            (username, ip_address, 1 if success else 0)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"Failed to record login attempt: {e}")


# ========== AUTHENTICATION DECORATORS ==========

def login_required(f):
    """Decorator to require login"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'username' not in session:
            if request.is_json:
                return jsonify({'error': 'Authentication required'}), 401
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function


def admin_required(f):
    """Decorator to require admin privileges"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'username' not in session:
            if request.is_json:
                return jsonify({'error': 'Authentication required'}), 401
            return redirect(url_for('login'))
        
        if not session.get('is_admin', False):
            if request.is_json:
                return jsonify({'error': 'Admin privileges required'}), 403
            flash('Admin privileges required', 'error')
            return redirect(url_for('dashboard'))
        
        return f(*args, **kwargs)
    return decorated_function


# ========== ROUTES - AUTHENTICATION ==========

@app.route('/')
def index():
    """Redirect to dashboard or login"""
    if 'username' in session:
        return redirect(url_for('dashboard'))
    return redirect(url_for('login'))


@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'GET':
        return render_template('login.html')
    
    try:
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')
        
        if not username or not password:
            return jsonify({'success': False, 'message': 'Username and password required'}), 400
        
        # Check login attempts
        if not check_login_attempts(username, request.remote_addr):
            return jsonify({'success': False, 'message': 'Too many failed login attempts. Please try again later.'}), 429
        
        # Authenticate against AD
        success, message = ad_integration.authenticate_user(username, password)
        
        # Record attempt
        record_login_attempt(username, request.remote_addr, success)
        
        if success:
            # Check if user is enabled
            if not ad_integration.check_user_enabled(username):
                return jsonify({'success': False, 'message': 'Account is disabled'}), 403
            
            # Set session
            session['username'] = username
            session['is_admin'] = ad_integration.verify_admin_user(username)
            session['login_time'] = datetime.now().isoformat()
            session.permanent = True
            
            # Log audit
            log_audit(username, 'login', details={'ip': request.remote_addr})
            
            logger.info(f"User logged in: {username} (admin: {session['is_admin']})")
            
            return jsonify({'success': True, 'redirect': url_for('dashboard')})
        else:
            return jsonify({'success': False, 'message': message}), 401
            
    except Exception as e:
        logger.error(f"Login error: {e}")
        return jsonify({'success': False, 'message': 'Internal server error'}), 500


@app.route('/logout')
def logout():
    """Logout user"""
    username = session.get('username')
    
    if username:
        log_audit(username, 'logout')
        logger.info(f"User logged out: {username}")
    
    session.clear()
    flash('Logged out successfully', 'success')
    return redirect(url_for('login'))


# ========== ROUTES - DASHBOARD ==========

@app.route('/dashboard')
@login_required
def dashboard():
    """Main dashboard"""
    return render_template('dashboard.html', 
                         username=session.get('username'),
                         is_admin=session.get('is_admin', False))


# ========== API ROUTES - USERS ==========

@app.route('/api/users', methods=['GET'])
@login_required
def api_list_users():
    """List all users"""
    try:
        users = samba_manager.list_users()
        
        # Enrich with quota information
        for user in users:
            try:
                quota = quota_engine.get_user_quota(user['username'])
                user['quota'] = quota
            except:
                user['quota'] = None
        
        return jsonify({'success': True, 'users': users})
        
    except Exception as e:
        logger.error(f"Failed to list users: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/users/<username>', methods=['GET'])
@login_required
def api_get_user(username):
    """Get user details"""
    try:
        user_info = samba_manager.get_user_info(username)
        quota_info = quota_engine.get_user_quota(username)
        groups = ad_integration.get_user_groups(username)
        
        return jsonify({
            'success': True,
            'user': user_info,
            'quota': quota_info,
            'groups': groups
        })
        
    except Exception as e:
        logger.error(f"Failed to get user {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/users', methods=['POST'])
@admin_required
def api_create_user():
    """Create new user"""
    try:
        data = request.get_json()
        
        username = data.get('username', '').strip()
        password = data.get('password', '')
        given_name = data.get('given_name', '').strip()
        surname = data.get('surname', '').strip()
        mail = data.get('mail', '').strip()
        must_change = data.get('must_change_password', True)
        
        if not username or not password:
            return jsonify({'success': False, 'message': 'Username and password required'}), 400
        
        # Validate password complexity
        valid, msg = ad_integration.validate_password_complexity(password)
        if not valid:
            return jsonify({'success': False, 'message': msg}), 400
        
        # Create user in AD
        samba_manager.create_user(username, password, given_name, surname, mail, must_change)
        
        # Set default quota
        try:
            quota_engine.set_user_quota(username, config.DEFAULT_SOFT_LIMIT, config.DEFAULT_HARD_LIMIT)
        except Exception as e:
            logger.warning(f"Failed to set quota for {username}: {e}")
        
        # Log audit
        log_audit(session['username'], 'user_create', username, 
                 {'given_name': given_name, 'surname': surname, 'mail': mail})
        
        return jsonify({'success': True, 'message': f'User {username} created successfully'})
        
    except SambaManagerException as e:
        logger.error(f"Failed to create user: {e}")
        log_audit(session['username'], 'user_create', username, status='failed')
        return jsonify({'success': False, 'message': str(e)}), 400
    except Exception as e:
        logger.error(f"Unexpected error creating user: {e}")
        return jsonify({'success': False, 'message': 'Internal server error'}), 500


@app.route('/api/users/<username>', methods=['DELETE'])
@admin_required
def api_delete_user(username):
    """Delete user"""
    try:
        # Prevent deletion of administrator
        if username.lower() == 'administrator':
            return jsonify({'success': False, 'message': 'Cannot delete administrator account'}), 400
        
        # Delete from AD
        samba_manager.delete_user(username)
        
        # Remove quota
        try:
            quota_engine.remove_user_quota(username)
        except Exception as e:
            logger.warning(f"Failed to remove quota for {username}: {e}")
        
        # Log audit
        log_audit(session['username'], 'user_delete', username)
        
        return jsonify({'success': True, 'message': f'User {username} deleted successfully'})
        
    except SambaManagerException as e:
        logger.error(f"Failed to delete user {username}: {e}")
        log_audit(session['username'], 'user_delete', username, status='failed')
        return jsonify({'success': False, 'message': str(e)}), 400
    except Exception as e:
        logger.error(f"Unexpected error deleting user: {e}")
        return jsonify({'success': False, 'message': 'Internal server error'}), 500


@app.route('/api/users/<username>/enable', methods=['POST'])
@admin_required
def api_enable_user(username):
    """Enable user account"""
    try:
        samba_manager.enable_user(username)
        log_audit(session['username'], 'user_enable', username)
        
        return jsonify({'success': True, 'message': f'User {username} enabled successfully'})
        
    except Exception as e:
        logger.error(f"Failed to enable user {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/users/<username>/disable', methods=['POST'])
@admin_required
def api_disable_user(username):
    """Disable user account"""
    try:
        if username.lower() == 'administrator':
            return jsonify({'success': False, 'message': 'Cannot disable administrator account'}), 400
        
        samba_manager.disable_user(username)
        log_audit(session['username'], 'user_disable', username)
        
        return jsonify({'success': True, 'message': f'User {username} disabled successfully'})
        
    except Exception as e:
        logger.error(f"Failed to disable user {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/users/<username>/reset-password', methods=['POST'])
@admin_required
def api_reset_password(username):
    """Reset user password"""
    try:
        data = request.get_json()
        new_password = data.get('password', '')
        must_change = data.get('must_change', True)
        
        if not new_password:
            return jsonify({'success': False, 'message': 'Password required'}), 400
        
        # Validate password complexity
        valid, msg = ad_integration.validate_password_complexity(new_password)
        if not valid:
            return jsonify({'success': False, 'message': msg}), 400
        
        samba_manager.set_password(username, new_password, must_change)
        log_audit(session['username'], 'password_reset', username)
        
        return jsonify({'success': True, 'message': f'Password reset for {username}'})
        
    except Exception as e:
        logger.error(f"Failed to reset password for {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


# ========== API ROUTES - GROUPS ==========

@app.route('/api/groups', methods=['GET'])
@login_required
def api_list_groups():
    """List all groups"""
    try:
        groups = samba_manager.list_groups()
        
        # Enrich with member count
        for group in groups:
            try:
                members = samba_manager.list_group_members(group['groupname'])
                group['member_count'] = len(members)
            except:
                group['member_count'] = 0
        
        return jsonify({'success': True, 'groups': groups})
        
    except Exception as e:
        logger.error(f"Failed to list groups: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/groups/<groupname>', methods=['GET'])
@login_required
def api_get_group(groupname):
    """Get group details"""
    try:
        members = samba_manager.list_group_members(groupname)
        
        return jsonify({
            'success': True,
            'group': {'groupname': groupname},
            'members': members
        })
        
    except Exception as e:
        logger.error(f"Failed to get group {groupname}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/groups', methods=['POST'])
@admin_required
def api_create_group():
    """Create new group"""
    try:
        data = request.get_json()
        
        groupname = data.get('groupname', '').strip()
        description = data.get('description', '').strip()
        
        if not groupname:
            return jsonify({'success': False, 'message': 'Group name required'}), 400
        
        samba_manager.create_group(groupname, description)
        log_audit(session['username'], 'group_create', groupname, {'description': description})
        
        return jsonify({'success': True, 'message': f'Group {groupname} created successfully'})
        
    except Exception as e:
        logger.error(f"Failed to create group: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/groups/<groupname>', methods=['DELETE'])
@admin_required
def api_delete_group(groupname):
    """Delete group"""
    try:
        # Prevent deletion of built-in groups
        protected_groups = ['Domain Admins', 'Domain Users', 'Administrators', 'Users']
        if groupname in protected_groups:
            return jsonify({'success': False, 'message': f'Cannot delete protected group {groupname}'}), 400
        
        samba_manager.delete_group(groupname)
        log_audit(session['username'], 'group_delete', groupname)
        
        return jsonify({'success': True, 'message': f'Group {groupname} deleted successfully'})
        
    except Exception as e:
        logger.error(f"Failed to delete group {groupname}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/groups/<groupname>/members', methods=['POST'])
@admin_required
def api_add_group_members(groupname):
    """Add members to group"""
    try:
        data = request.get_json()
        usernames = data.get('usernames', [])
        
        if not usernames:
            return jsonify({'success': False, 'message': 'No usernames provided'}), 400
        
        samba_manager.add_group_members(groupname, usernames)
        log_audit(session['username'], 'group_add_members', groupname, {'members': usernames})
        
        return jsonify({'success': True, 'message': f'Added {len(usernames)} member(s) to {groupname}'})
        
    except Exception as e:
        logger.error(f"Failed to add members to {groupname}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/groups/<groupname>/members/<username>', methods=['DELETE'])
@admin_required
def api_remove_group_member(groupname, username):
    """Remove member from group"""
    try:
        samba_manager.remove_group_members(groupname, [username])
        log_audit(session['username'], 'group_remove_member', groupname, {'member': username})
        
        return jsonify({'success': True, 'message': f'Removed {username} from {groupname}'})
        
    except Exception as e:
        logger.error(f"Failed to remove {username} from {groupname}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


# ========== API ROUTES - QUOTAS ==========

@app.route('/api/quotas', methods=['GET'])
@login_required
def api_list_quotas():
    """List all quotas"""
    try:
        quotas = quota_engine.get_all_quotas()
        return jsonify({'success': True, 'quotas': quotas})
        
    except Exception as e:
        logger.error(f"Failed to list quotas: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/quotas/<username>', methods=['GET'])
@login_required
def api_get_quota(username):
    """Get user quota"""
    try:
        quota = quota_engine.get_user_quota(username)
        status = quota_engine.check_quota_status(username)
        
        return jsonify({
            'success': True,
            'quota': quota,
            'status': status
        })
        
    except Exception as e:
        logger.error(f"Failed to get quota for {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/quotas/<username>', methods=['POST'])
@admin_required
def api_set_quota(username):
    """Set user quota"""
    try:
        data = request.get_json()
        
        soft_limit = int(data.get('soft_limit', 0))
        hard_limit = int(data.get('hard_limit', 0))
        
        if soft_limit <= 0 or hard_limit <= 0:
            return jsonify({'success': False, 'message': 'Invalid quota limits'}), 400
        
        if soft_limit > hard_limit:
            return jsonify({'success': False, 'message': 'Soft limit cannot exceed hard limit'}), 400
        
        quota_engine.set_user_quota(username, soft_limit, hard_limit)
        
        # Update database
        conn = get_db()
        conn.execute(
            'INSERT OR REPLACE INTO user_quotas (username, soft_limit, hard_limit, last_updated) VALUES (?, ?, ?, ?)',
            (username, soft_limit, hard_limit, datetime.now())
        )
        conn.commit()
        conn.close()
        
        log_audit(session['username'], 'quota_set', username, 
                 {'soft_limit': soft_limit, 'hard_limit': hard_limit})
        
        return jsonify({'success': True, 'message': f'Quota set for {username}'})
        
    except Exception as e:
        logger.error(f"Failed to set quota for {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/quotas/<username>/usage', methods=['GET'])
@login_required
def api_get_usage(username):
    """Get user disk usage"""
    try:
        quota = quota_engine.get_user_quota(username)
        
        usage_data = {
            'username': username,
            'used_mb': quota['used_mb'],
            'soft_limit_mb': quota['soft_limit_mb'],
            'hard_limit_mb': quota['hard_limit_mb'],
            'percentage': round((quota['used_mb'] / quota['hard_limit_mb'] * 100), 2) if quota['hard_limit_mb'] > 0 else 0,
            'available_mb': max(0, quota['hard_limit_mb'] - quota['used_mb'])
        }
        
        return jsonify({'success': True, 'usage': usage_data})
        
    except Exception as e:
        logger.error(f"Failed to get usage for {username}: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/quota-policies', methods=['GET'])
@login_required
def api_list_quota_policies():
    """List quota policies"""
    try:
        conn = get_db()
        cursor = conn.execute('SELECT * FROM quota_policies ORDER BY policy_name')
        policies = [dict(row) for row in cursor.fetchall()]
        conn.close()
        
        return jsonify({'success': True, 'policies': policies})
        
    except Exception as e:
        logger.error(f"Failed to list quota policies: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/quota-policies', methods=['POST'])
@admin_required
def api_create_quota_policy():
    """Create quota policy"""
    try:
        data = request.get_json()
        
        policy_name = data.get('policy_name', '').strip()
        soft_limit = int(data.get('soft_limit', 0))
        hard_limit = int(data.get('hard_limit', 0))
        description = data.get('description', '').strip()
        
        if not policy_name or soft_limit <= 0 or hard_limit <= 0:
            return jsonify({'success': False, 'message': 'Invalid policy data'}), 400
        
        conn = get_db()
        conn.execute(
            'INSERT INTO quota_policies (policy_name, soft_limit, hard_limit, description) VALUES (?, ?, ?, ?)',
            (policy_name, soft_limit, hard_limit, description)
        )
        conn.commit()
        conn.close()
        
        log_audit(session['username'], 'quota_policy_create', policy_name)
        
        return jsonify({'success': True, 'message': f'Policy {policy_name} created successfully'})
        
    except sqlite3.IntegrityError:
        return jsonify({'success': False, 'message': 'Policy name already exists'}), 400
    except Exception as e:
        logger.error(f"Failed to create quota policy: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


# ========== API ROUTES - MONITORING ==========

@app.route('/api/monitoring/system', methods=['GET'])
@login_required
def api_system_metrics():
    """Get system metrics"""
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage(config.QUOTA_FILESYSTEM)
        
        # Get load average
        load_avg = os.getloadavg() if hasattr(os, 'getloadavg') else (0, 0, 0)
        
        metrics = {
            'cpu': {
                'percent': cpu_percent,
                'count': psutil.cpu_count()
            },
            'memory': {
                'total': memory.total,
                'used': memory.used,
                'available': memory.available,
                'percent': memory.percent
            },
            'disk': {
                'total': disk.total,
                'used': disk.used,
                'free': disk.free,
                'percent': disk.percent
            },
            'load_average': {
                '1min': load_avg[0],
                '5min': load_avg[1],
                '15min': load_avg[2]
            },
            'timestamp': datetime.now().isoformat()
        }
        
        return jsonify({'success': True, 'metrics': metrics})
        
    except Exception as e:
        logger.error(f"Failed to get system metrics: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/monitoring/services', methods=['GET'])
@login_required
def api_service_status():
    """Get service status"""
    try:
        services = ['samba', 'smbd', 'nmbd', 'winbind', 'nfs-server']
        status_list = []
        
        for service in services:
            try:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                
                is_active = result.stdout.strip() == 'active'
                
                status_list.append({
                    'name': service,
                    'status': 'running' if is_active else 'stopped',
                    'active': is_active
                })
            except:
                status_list.append({
                    'name': service,
                    'status': 'unknown',
                    'active': False
                })
        
        return jsonify({'success': True, 'services': status_list})
        
    except Exception as e:
        logger.error(f"Failed to get service status: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/monitoring/storage', methods=['GET'])
@login_required
def api_storage_usage():
    """Get storage usage"""
    try:
        filesystem = quota_engine.get_filesystem_usage()
        top_users = quota_engine.get_top_users(10)
        
        return jsonify({
            'success': True,
            'filesystem': filesystem,
            'top_users': top_users
        })
        
    except Exception as e:
        logger.error(f"Failed to get storage usage: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/monitoring/sessions', methods=['GET'])
@admin_required
def api_active_sessions():
    """Get active user sessions"""
    try:
        # Get sessions from database
        conn = get_db()
        cursor = conn.execute(
            'SELECT username, ip_address, created_at, last_activity FROM user_sessions WHERE expires_at > ? ORDER BY last_activity DESC',
            (datetime.now(),)
        )
        sessions = [dict(row) for row in cursor.fetchall()]
        conn.close()
        
        # Also check for Samba sessions
        try:
            result = subprocess.run(
                ['smbstatus', '--brief'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            samba_sessions = []
            for line in result.stdout.split('\n'):
                if line.strip() and not line.startswith('---') and 'PID' not in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        samba_sessions.append({
                            'username': parts[1] if len(parts) > 1 else 'unknown',
                            'machine': parts[2] if len(parts) > 2 else 'unknown',
                            'protocol': parts[3] if len(parts) > 3 else 'unknown'
                        })
        except:
            samba_sessions = []
        
        return jsonify({
            'success': True,
            'web_sessions': sessions,
            'samba_sessions': samba_sessions
        })
        
    except Exception as e:
        logger.error(f"Failed to get active sessions: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/monitoring/audit-log', methods=['GET'])
@admin_required
def api_audit_log():
    """Get audit log entries"""
    try:
        limit = request.args.get('limit', 100, type=int)
        offset = request.args.get('offset', 0, type=int)
        
        conn = get_db()
        cursor = conn.execute(
            'SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT ? OFFSET ?',
            (limit, offset)
        )
        logs = [dict(row) for row in cursor.fetchall()]
        
        # Get total count
        total = conn.execute('SELECT COUNT(*) FROM audit_log').fetchone()[0]
        
        conn.close()
        
        return jsonify({
            'success': True,
            'logs': logs,
            'total': total,
            'limit': limit,
            'offset': offset
        })
        
    except Exception as e:
        logger.error(f"Failed to get audit log: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


# ========== PAGE ROUTES ==========

@app.route('/users')
@login_required
def users_page():
    """Users management page"""
    return render_template('users/list.html',
                         username=session.get('username'),
                         is_admin=session.get('is_admin', False))


@app.route('/groups')
@login_required
def groups_page():
    """Groups management page"""
    return render_template('groups/list.html',
                         username=session.get('username'),
                         is_admin=session.get('is_admin', False))


@app.route('/quotas')
@login_required
def quotas_page():
    """Quotas management page"""
    return render_template('quotas/list.html',
                         username=session.get('username'),
                         is_admin=session.get('is_admin', False))


@app.route('/monitoring')
@login_required
def monitoring_page():
    """Monitoring dashboard page"""
    return render_template('monitoring/dashboard.html',
                         username=session.get('username'),
                         is_admin=session.get('is_admin', False))


@app.route('/reports')
@admin_required
def reports_page():
    """Reports dashboard page"""
    return render_template('reports/dashboard.html',
                         username=session.get('username'),
                         is_admin=session.get('is_admin', False))


# ========== ERROR HANDLERS ==========

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    if request.is_json:
        return jsonify({'error': 'Not found'}), 404
    return render_template('base.html', error='Page not found'), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.error(f"Internal error: {error}")
    if request.is_json:
        return jsonify({'error': 'Internal server error'}), 500
    return render_template('base.html', error='Internal server error'), 500


# ========== UTILITY ROUTES ==========

@app.route('/api/domain/info', methods=['GET'])
@admin_required
def api_domain_info():
    """Get domain information"""
    try:
        domain_info = samba_manager.get_domain_info()
        password_policy = ad_integration.get_password_policy()
        
        return jsonify({
            'success': True,
            'domain': domain_info,
            'password_policy': password_policy
        })
        
    except Exception as e:
        logger.error(f"Failed to get domain info: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/test-connection', methods=['GET'])
@admin_required
def api_test_connection():
    """Test AD connection"""
    try:
        success, message = ad_integration.test_connection()
        
        return jsonify({
            'success': success,
            'message': message
        })
        
    except Exception as e:
        logger.error(f"Connection test failed: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


if __name__ == '__main__':
    # Initialize database on first run
    if not os.path.exists(config.DATABASE_PATH):
        init_db()
    
    app.run(host='0.0.0.0', port=5000, debug=config.DEBUG)
