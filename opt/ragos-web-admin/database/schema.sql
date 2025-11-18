-- RAGOS Web Admin Database Schema
-- SQLite database for storing metadata, quotas, and audit logs
-- Active Directory remains the source of truth for users/groups

-- Users metadata table (supplementary information not in AD)
CREATE TABLE IF NOT EXISTS users_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    email TEXT,
    department TEXT,
    phone TEXT,
    location TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Quota policies (templates for applying quotas)
CREATE TABLE IF NOT EXISTS quota_policies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    policy_name TEXT UNIQUE NOT NULL,
    soft_limit INTEGER NOT NULL,  -- in MB
    hard_limit INTEGER NOT NULL,  -- in MB
    description TEXT,
    is_default INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User quotas (actual quota assignments)
CREATE TABLE IF NOT EXISTS user_quotas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    soft_limit INTEGER NOT NULL,  -- in MB
    hard_limit INTEGER NOT NULL,  -- in MB
    current_usage INTEGER DEFAULT 0,  -- in MB, updated periodically
    policy_id INTEGER,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (policy_id) REFERENCES quota_policies(id) ON DELETE SET NULL
);

-- Audit log (all administrative actions)
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,  -- who performed the action
    action TEXT NOT NULL,     -- what action was performed
    target TEXT,              -- who/what was affected
    details TEXT,             -- additional information (JSON format)
    ip_address TEXT,
    status TEXT DEFAULT 'success',  -- success, failed, error
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- System configuration key-value store
CREATE TABLE IF NOT EXISTS system_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by TEXT
);

-- Login attempts tracking (security)
CREATE TABLE IF NOT EXISTS login_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    success INTEGER DEFAULT 0,  -- 0 = failed, 1 = success
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Session management
CREATE TABLE IF NOT EXISTS user_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    session_id TEXT UNIQUE NOT NULL,
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_audit_username ON audit_log(username);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_login_attempts_username ON login_attempts(username);
CREATE INDEX IF NOT EXISTS idx_login_attempts_timestamp ON login_attempts(timestamp);
CREATE INDEX IF NOT EXISTS idx_user_sessions_username ON user_sessions(username);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON user_sessions(expires_at);

-- Insert default configuration values
INSERT OR IGNORE INTO system_config (key, value, description) VALUES
    ('maintenance_mode', 'false', 'Enable/disable maintenance mode'),
    ('allow_user_registration', 'false', 'Allow self-service user registration'),
    ('password_min_length', '8', 'Minimum password length'),
    ('password_complexity', 'true', 'Require complex passwords'),
    ('session_timeout', '1800', 'Session timeout in seconds'),
    ('max_login_attempts', '5', 'Maximum failed login attempts'),
    ('lockout_duration', '300', 'Account lockout duration in seconds'),
    ('enable_audit_log', 'true', 'Enable audit logging'),
    ('quota_warning_threshold', '80', 'Quota warning threshold percentage'),
    ('app_version', '1.0.0', 'Application version');

-- Insert default quota policies
INSERT OR IGNORE INTO quota_policies (policy_name, soft_limit, hard_limit, description, is_default) VALUES
    ('Default User', 5120, 10240, 'Default quota for regular users (5GB soft, 10GB hard)', 1),
    ('Power User', 10240, 20480, 'Quota for power users (10GB soft, 20GB hard)', 0),
    ('Administrator', 20480, 51200, 'Quota for administrators (20GB soft, 50GB hard)', 0),
    ('Guest', 1024, 2048, 'Limited quota for guest accounts (1GB soft, 2GB hard)', 0),
    ('Developer', 15360, 30720, 'Quota for developers (15GB soft, 30GB hard)', 0);

-- Create trigger to update timestamp on users_metadata update
CREATE TRIGGER IF NOT EXISTS update_users_metadata_timestamp 
AFTER UPDATE ON users_metadata
BEGIN
    UPDATE users_metadata SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Create trigger to update timestamp on quota_policies update
CREATE TRIGGER IF NOT EXISTS update_quota_policies_timestamp 
AFTER UPDATE ON quota_policies
BEGIN
    UPDATE quota_policies SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- Create trigger to clean old login attempts (keep last 30 days)
CREATE TRIGGER IF NOT EXISTS cleanup_old_login_attempts
AFTER INSERT ON login_attempts
BEGIN
    DELETE FROM login_attempts 
    WHERE timestamp < datetime('now', '-30 days');
END;

-- Create trigger to clean expired sessions
CREATE TRIGGER IF NOT EXISTS cleanup_expired_sessions
AFTER INSERT ON user_sessions
BEGIN
    DELETE FROM user_sessions 
    WHERE expires_at < datetime('now');
END;
