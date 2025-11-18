"""
RAGOS Web Admin - Samba Manager
=================================
Wrapper functions for samba-tool commands
"""

import subprocess
import json
import re
import logging
from typing import List, Dict, Optional, Tuple

logger = logging.getLogger(__name__)


class SambaManagerException(Exception):
    """Custom exception for Samba operations"""
    pass


class SambaManager:
    """Manager class for Samba AD operations using samba-tool"""
    
    def __init__(self, samba_tool_path: str = '/usr/bin/samba-tool'):
        """
        Initialize Samba Manager
        
        Args:
            samba_tool_path: Path to samba-tool binary
        """
        self.samba_tool = samba_tool_path
        
    def _run_command(self, args: List[str], check: bool = True) -> Tuple[int, str, str]:
        """
        Run a samba-tool command safely
        
        Args:
            args: Command arguments as list
            check: Whether to raise exception on non-zero exit
            
        Returns:
            Tuple of (returncode, stdout, stderr)
        """
        try:
            cmd = [self.samba_tool] + args
            logger.debug(f"Running command: {' '.join(cmd)}")
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if check and result.returncode != 0:
                logger.error(f"Command failed: {result.stderr}")
                raise SambaManagerException(f"Command failed: {result.stderr}")
            
            return result.returncode, result.stdout, result.stderr
            
        except subprocess.TimeoutExpired:
            logger.error("Command timed out")
            raise SambaManagerException("Command timed out after 30 seconds")
        except FileNotFoundError:
            logger.error(f"samba-tool not found at {self.samba_tool}")
            raise SambaManagerException(f"samba-tool not found at {self.samba_tool}")
        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}")
            raise SambaManagerException(f"Unexpected error: {str(e)}")
    
    # ========== USER MANAGEMENT ==========
    
    def list_users(self) -> List[Dict[str, str]]:
        """
        List all users in AD
        
        Returns:
            List of user dictionaries with username and attributes
        """
        try:
            _, stdout, _ = self._run_command(['user', 'list'])
            users = []
            
            for line in stdout.strip().split('\n'):
                username = line.strip()
                if username and not username.startswith('#'):
                    users.append({'username': username})
            
            logger.info(f"Listed {len(users)} users")
            return users
            
        except Exception as e:
            logger.error(f"Failed to list users: {str(e)}")
            raise
    
    def get_user_info(self, username: str) -> Dict[str, str]:
        """
        Get detailed information about a user
        
        Args:
            username: Username to query
            
        Returns:
            Dictionary with user attributes
        """
        try:
            _, stdout, _ = self._run_command(['user', 'show', username])
            
            user_info = {'username': username}
            for line in stdout.strip().split('\n'):
                if ':' in line:
                    key, value = line.split(':', 1)
                    user_info[key.strip()] = value.strip()
            
            logger.info(f"Retrieved info for user: {username}")
            return user_info
            
        except Exception as e:
            logger.error(f"Failed to get user info for {username}: {str(e)}")
            raise
    
    def create_user(self, username: str, password: str, 
                   given_name: str = None, surname: str = None,
                   mail: str = None, must_change_password: bool = True) -> bool:
        """
        Create a new user in AD
        
        Args:
            username: Username for new user
            password: Initial password
            given_name: First name
            surname: Last name
            mail: Email address
            must_change_password: Force password change on first login
            
        Returns:
            True if successful
        """
        try:
            args = ['user', 'create', username, password]
            
            if given_name:
                args.extend(['--given-name', given_name])
            if surname:
                args.extend(['--surname', surname])
            if mail:
                args.extend(['--mail-address', mail])
            if must_change_password:
                args.append('--must-change-at-next-login')
            
            self._run_command(args)
            logger.info(f"Created user: {username}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create user {username}: {str(e)}")
            raise
    
    def delete_user(self, username: str) -> bool:
        """
        Delete a user from AD
        
        Args:
            username: Username to delete
            
        Returns:
            True if successful
        """
        try:
            self._run_command(['user', 'delete', username])
            logger.info(f"Deleted user: {username}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete user {username}: {str(e)}")
            raise
    
    def enable_user(self, username: str) -> bool:
        """
        Enable a user account
        
        Args:
            username: Username to enable
            
        Returns:
            True if successful
        """
        try:
            self._run_command(['user', 'enable', username])
            logger.info(f"Enabled user: {username}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to enable user {username}: {str(e)}")
            raise
    
    def disable_user(self, username: str) -> bool:
        """
        Disable a user account
        
        Args:
            username: Username to disable
            
        Returns:
            True if successful
        """
        try:
            self._run_command(['user', 'disable', username])
            logger.info(f"Disabled user: {username}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to disable user {username}: {str(e)}")
            raise
    
    def set_password(self, username: str, new_password: str, 
                    must_change: bool = False) -> bool:
        """
        Set/reset user password
        
        Args:
            username: Username
            new_password: New password
            must_change: Force password change on next login
            
        Returns:
            True if successful
        """
        try:
            args = ['user', 'setpassword', username, 
                   '--newpassword', new_password]
            
            if must_change:
                args.append('--must-change-at-next-login')
            
            self._run_command(args)
            logger.info(f"Set password for user: {username}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to set password for {username}: {str(e)}")
            raise
    
    # ========== GROUP MANAGEMENT ==========
    
    def list_groups(self) -> List[Dict[str, str]]:
        """
        List all groups in AD
        
        Returns:
            List of group dictionaries
        """
        try:
            _, stdout, _ = self._run_command(['group', 'list'])
            groups = []
            
            for line in stdout.strip().split('\n'):
                groupname = line.strip()
                if groupname and not groupname.startswith('#'):
                    groups.append({'groupname': groupname})
            
            logger.info(f"Listed {len(groups)} groups")
            return groups
            
        except Exception as e:
            logger.error(f"Failed to list groups: {str(e)}")
            raise
    
    def create_group(self, groupname: str, description: str = None) -> bool:
        """
        Create a new group in AD
        
        Args:
            groupname: Name for new group
            description: Group description
            
        Returns:
            True if successful
        """
        try:
            args = ['group', 'add', groupname]
            
            if description:
                args.extend(['--description', description])
            
            self._run_command(args)
            logger.info(f"Created group: {groupname}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create group {groupname}: {str(e)}")
            raise
    
    def delete_group(self, groupname: str) -> bool:
        """
        Delete a group from AD
        
        Args:
            groupname: Group name to delete
            
        Returns:
            True if successful
        """
        try:
            self._run_command(['group', 'delete', groupname])
            logger.info(f"Deleted group: {groupname}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete group {groupname}: {str(e)}")
            raise
    
    def list_group_members(self, groupname: str) -> List[str]:
        """
        List members of a group
        
        Args:
            groupname: Group name
            
        Returns:
            List of usernames
        """
        try:
            _, stdout, _ = self._run_command(['group', 'listmembers', groupname])
            members = [line.strip() for line in stdout.strip().split('\n') 
                      if line.strip() and not line.startswith('#')]
            
            logger.info(f"Listed {len(members)} members of group: {groupname}")
            return members
            
        except Exception as e:
            logger.error(f"Failed to list members of {groupname}: {str(e)}")
            raise
    
    def add_group_members(self, groupname: str, usernames: List[str]) -> bool:
        """
        Add members to a group
        
        Args:
            groupname: Group name
            usernames: List of usernames to add
            
        Returns:
            True if successful
        """
        try:
            members_str = ','.join(usernames)
            self._run_command(['group', 'addmembers', groupname, members_str])
            logger.info(f"Added members to {groupname}: {usernames}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add members to {groupname}: {str(e)}")
            raise
    
    def remove_group_members(self, groupname: str, usernames: List[str]) -> bool:
        """
        Remove members from a group
        
        Args:
            groupname: Group name
            usernames: List of usernames to remove
            
        Returns:
            True if successful
        """
        try:
            members_str = ','.join(usernames)
            self._run_command(['group', 'removemembers', groupname, members_str])
            logger.info(f"Removed members from {groupname}: {usernames}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to remove members from {groupname}: {str(e)}")
            raise
    
    # ========== DOMAIN INFORMATION ==========
    
    def get_domain_info(self) -> Dict[str, str]:
        """
        Get domain information
        
        Returns:
            Dictionary with domain details
        """
        try:
            _, stdout, _ = self._run_command(['domain', 'info', '127.0.0.1'])
            
            domain_info = {}
            for line in stdout.strip().split('\n'):
                if ':' in line:
                    key, value = line.split(':', 1)
                    domain_info[key.strip()] = value.strip()
            
            logger.info("Retrieved domain information")
            return domain_info
            
        except Exception as e:
            logger.error(f"Failed to get domain info: {str(e)}")
            raise
    
    def get_domain_level(self) -> str:
        """
        Get domain functional level
        
        Returns:
            Domain level string
        """
        try:
            _, stdout, _ = self._run_command(['domain', 'level', 'show'])
            return stdout.strip()
            
        except Exception as e:
            logger.error(f"Failed to get domain level: {str(e)}")
            raise
