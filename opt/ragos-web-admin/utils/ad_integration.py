"""
RAGOS Web Admin - AD Integration
==================================
Active Directory authentication and integration
"""

import subprocess
import logging
import os
from typing import Optional, Tuple

logger = logging.getLogger(__name__)


class ADAuthException(Exception):
    """Custom exception for AD authentication"""
    pass


class ADIntegration:
    """Manager class for AD authentication and integration"""
    
    def __init__(self, domain: str = 'RAGOS.INTRA', 
                 realm: str = 'RAGOS.INTRA',
                 server: str = '10.0.3.1'):
        """
        Initialize AD Integration
        
        Args:
            domain: AD domain name
            realm: Kerberos realm
            server: AD server IP
        """
        self.domain = domain
        self.realm = realm
        self.server = server
    
    def authenticate_user(self, username: str, password: str) -> Tuple[bool, str]:
        """
        Authenticate user against Active Directory using Kerberos
        
        Args:
            username: Username to authenticate
            password: User password
            
        Returns:
            Tuple of (success, message)
        """
        try:
            # Use kinit to authenticate
            principal = f"{username}@{self.realm}"
            
            logger.debug(f"Attempting authentication for {principal}")
            
            # Create kinit process
            process = subprocess.Popen(
                ['kinit', principal],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            # Send password
            stdout, stderr = process.communicate(input=password + '\n', timeout=10)
            
            if process.returncode == 0:
                logger.info(f"Authentication successful for {username}")
                
                # Destroy ticket after validation
                subprocess.run(['kdestroy'], capture_output=True, timeout=5)
                
                return True, "Authentication successful"
            else:
                logger.warning(f"Authentication failed for {username}: {stderr}")
                return False, f"Authentication failed: {stderr.strip()}"
            
        except subprocess.TimeoutExpired:
            logger.error("Authentication timed out")
            return False, "Authentication timed out"
        except FileNotFoundError:
            logger.error("kinit not found - Kerberos client not installed")
            return False, "Kerberos client not installed"
        except Exception as e:
            logger.error(f"Authentication error: {str(e)}")
            return False, f"Authentication error: {str(e)}"
    
    def verify_admin_user(self, username: str) -> bool:
        """
        Verify if user is a member of Domain Admins group
        
        Args:
            username: Username to verify
            
        Returns:
            True if user is admin
        """
        try:
            # Check group membership using samba-tool
            result = subprocess.run(
                ['samba-tool', 'group', 'listmembers', 'Domain Admins'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                members = result.stdout.strip().split('\n')
                is_admin = username in members or username.lower() == 'administrator'
                
                logger.info(f"Admin verification for {username}: {is_admin}")
                return is_admin
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to verify admin status: {str(e)}")
            return False
    
    def get_user_groups(self, username: str) -> list:
        """
        Get list of groups user belongs to
        
        Args:
            username: Username
            
        Returns:
            List of group names
        """
        try:
            # Use samba-tool to list user's groups
            result = subprocess.run(
                ['samba-tool', 'user', 'show', username],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                return []
            
            groups = []
            for line in result.stdout.split('\n'):
                if line.startswith('memberOf:'):
                    # Extract group name from DN
                    # Example: memberOf: CN=Domain Admins,CN=Users,DC=RAGOS,DC=INTRA
                    dn = line.split(':', 1)[1].strip()
                    if dn.startswith('CN='):
                        group_name = dn.split(',')[0].replace('CN=', '')
                        groups.append(group_name)
            
            logger.info(f"Retrieved {len(groups)} groups for {username}")
            return groups
            
        except Exception as e:
            logger.error(f"Failed to get user groups: {str(e)}")
            return []
    
    def check_user_enabled(self, username: str) -> bool:
        """
        Check if user account is enabled
        
        Args:
            username: Username to check
            
        Returns:
            True if enabled
        """
        try:
            result = subprocess.run(
                ['samba-tool', 'user', 'show', username],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0:
                return False
            
            # Check for userAccountControl flags
            # Bit 2 (0x2) = ACCOUNTDISABLE
            for line in result.stdout.split('\n'):
                if 'userAccountControl:' in line:
                    try:
                        uac = int(line.split(':')[1].strip())
                        # Check if ACCOUNTDISABLE flag is NOT set
                        is_enabled = (uac & 0x2) == 0
                        logger.info(f"User {username} enabled status: {is_enabled}")
                        return is_enabled
                    except ValueError:
                        pass
            
            # Default to enabled if flag not found
            return True
            
        except Exception as e:
            logger.error(f"Failed to check user enabled status: {str(e)}")
            return False
    
    def test_connection(self) -> Tuple[bool, str]:
        """
        Test connection to AD server
        
        Returns:
            Tuple of (success, message)
        """
        try:
            # Try to get domain info
            result = subprocess.run(
                ['samba-tool', 'domain', 'info', self.server],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                logger.info("AD connection test successful")
                return True, "Connection to AD successful"
            else:
                logger.warning(f"AD connection test failed: {result.stderr}")
                return False, f"Connection failed: {result.stderr.strip()}"
            
        except Exception as e:
            logger.error(f"AD connection test error: {str(e)}")
            return False, f"Connection error: {str(e)}"
    
    def get_password_policy(self) -> dict:
        """
        Get domain password policy
        
        Returns:
            Dictionary with password policy settings
        """
        try:
            result = subprocess.run(
                ['samba-tool', 'domain', 'passwordsettings', 'show'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            policy = {}
            
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if ':' in line:
                        key, value = line.split(':', 1)
                        policy[key.strip()] = value.strip()
            
            logger.info("Retrieved password policy")
            return policy
            
        except Exception as e:
            logger.error(f"Failed to get password policy: {str(e)}")
            return {}
    
    def validate_password_complexity(self, password: str) -> Tuple[bool, str]:
        """
        Validate password against complexity requirements
        
        Args:
            password: Password to validate
            
        Returns:
            Tuple of (valid, message)
        """
        # Basic password complexity rules
        if len(password) < 8:
            return False, "Password must be at least 8 characters"
        
        has_upper = any(c.isupper() for c in password)
        has_lower = any(c.islower() for c in password)
        has_digit = any(c.isdigit() for c in password)
        has_special = any(c in '!@#$%^&*()_+-=[]{}|;:,.<>?' for c in password)
        
        complexity_count = sum([has_upper, has_lower, has_digit, has_special])
        
        if complexity_count < 3:
            return False, "Password must contain at least 3 of: uppercase, lowercase, digit, special character"
        
        return True, "Password meets complexity requirements"
