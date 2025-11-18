"""
RAGOS Web Admin - Quota Engine
================================
Quota management for user home directories
"""

import subprocess
import re
import logging
import os
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class QuotaException(Exception):
    """Custom exception for quota operations"""
    pass


class QuotaEngine:
    """Manager class for disk quota operations"""
    
    def __init__(self, filesystem: str = '/mnt/ragostorage',
                 setquota_cmd: str = '/usr/bin/setquota',
                 quota_cmd: str = '/usr/bin/quota',
                 repquota_cmd: str = '/usr/bin/repquota'):
        """
        Initialize Quota Engine
        
        Args:
            filesystem: Mount point for quota filesystem
            setquota_cmd: Path to setquota binary
            quota_cmd: Path to quota binary
            repquota_cmd: Path to repquota binary
        """
        self.filesystem = filesystem
        self.setquota_cmd = setquota_cmd
        self.quota_cmd = quota_cmd
        self.repquota_cmd = repquota_cmd
    
    def _run_command(self, args: List[str], check: bool = True) -> Tuple[int, str, str]:
        """
        Run a quota command safely
        
        Args:
            args: Command arguments as list
            check: Whether to raise exception on non-zero exit
            
        Returns:
            Tuple of (returncode, stdout, stderr)
        """
        try:
            logger.debug(f"Running command: {' '.join(args)}")
            
            result = subprocess.run(
                args,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if check and result.returncode != 0:
                logger.error(f"Command failed: {result.stderr}")
                raise QuotaException(f"Command failed: {result.stderr}")
            
            return result.returncode, result.stdout, result.stderr
            
        except subprocess.TimeoutExpired:
            logger.error("Command timed out")
            raise QuotaException("Command timed out after 30 seconds")
        except FileNotFoundError as e:
            logger.error(f"Command not found: {e}")
            raise QuotaException(f"Command not found: {e}")
        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}")
            raise QuotaException(f"Unexpected error: {str(e)}")
    
    def _kb_to_mb(self, kb: int) -> int:
        """Convert kilobytes to megabytes"""
        return kb // 1024
    
    def _mb_to_kb(self, mb: int) -> int:
        """Convert megabytes to kilobytes"""
        return mb * 1024
    
    def set_user_quota(self, username: str, soft_limit_mb: int, 
                       hard_limit_mb: int) -> bool:
        """
        Set quota for a user
        
        Args:
            username: Username
            soft_limit_mb: Soft limit in MB
            hard_limit_mb: Hard limit in MB
            
        Returns:
            True if successful
        """
        try:
            # Convert MB to KB for quota commands
            soft_kb = self._mb_to_kb(soft_limit_mb)
            hard_kb = self._mb_to_kb(hard_limit_mb)
            
            args = [
                self.setquota_cmd,
                '-u', username,
                str(soft_kb), str(hard_kb),
                '0', '0',  # inode limits (not used)
                self.filesystem
            ]
            
            self._run_command(args)
            logger.info(f"Set quota for {username}: {soft_limit_mb}MB/{hard_limit_mb}MB")
            return True
            
        except Exception as e:
            logger.error(f"Failed to set quota for {username}: {str(e)}")
            raise
    
    def get_user_quota(self, username: str) -> Dict[str, any]:
        """
        Get quota information for a user
        
        Args:
            username: Username
            
        Returns:
            Dictionary with quota information (in MB)
        """
        try:
            args = [self.quota_cmd, '-u', username, '-w', '-p']
            
            returncode, stdout, stderr = self._run_command(args, check=False)
            
            # Parse quota output
            quota_info = {
                'username': username,
                'used_mb': 0,
                'soft_limit_mb': 0,
                'hard_limit_mb': 0,
                'grace': '',
                'filesystem': self.filesystem
            }
            
            # Example output format:
            # Disk quotas for user testuser (uid 10000):
            #     Filesystem   blocks   quota   limit   grace   files   quota   limit   grace
            #     /dev/sda1     12345   51200   102400            100       0       0
            
            for line in stdout.split('\n'):
                if self.filesystem in line or '/dev/' in line:
                    parts = line.split()
                    if len(parts) >= 4:
                        try:
                            used_kb = int(parts[1])
                            soft_kb = int(parts[2]) if parts[2].isdigit() else 0
                            hard_kb = int(parts[3]) if parts[3].isdigit() else 0
                            
                            quota_info['used_mb'] = self._kb_to_mb(used_kb)
                            quota_info['soft_limit_mb'] = self._kb_to_mb(soft_kb)
                            quota_info['hard_limit_mb'] = self._kb_to_mb(hard_kb)
                            
                            if len(parts) > 4 and parts[4] != 'files':
                                quota_info['grace'] = parts[4]
                            
                            break
                        except (ValueError, IndexError):
                            continue
            
            logger.info(f"Retrieved quota for {username}: {quota_info['used_mb']}MB used")
            return quota_info
            
        except Exception as e:
            logger.error(f"Failed to get quota for {username}: {str(e)}")
            # Return default structure on error
            return {
                'username': username,
                'used_mb': 0,
                'soft_limit_mb': 0,
                'hard_limit_mb': 0,
                'grace': '',
                'filesystem': self.filesystem,
                'error': str(e)
            }
    
    def remove_user_quota(self, username: str) -> bool:
        """
        Remove quota for a user (set to 0)
        
        Args:
            username: Username
            
        Returns:
            True if successful
        """
        try:
            args = [
                self.setquota_cmd,
                '-u', username,
                '0', '0', '0', '0',
                self.filesystem
            ]
            
            self._run_command(args)
            logger.info(f"Removed quota for {username}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to remove quota for {username}: {str(e)}")
            raise
    
    def get_all_quotas(self) -> List[Dict[str, any]]:
        """
        Get quota information for all users
        
        Returns:
            List of dictionaries with quota information
        """
        try:
            args = [self.repquota_cmd, '-u', self.filesystem]
            
            returncode, stdout, stderr = self._run_command(args, check=False)
            
            quotas = []
            
            # Example output:
            # *** Report for user quotas on device /dev/sda1
            # Block grace time: 7days; Inode grace time: 7days
            #                         Block limits                File limits
            # User            used    soft    hard  grace    used  soft  hard  grace
            # ----------------------------------------------------------------------
            # root      --  123456       0       0          12345     0     0
            # testuser  --   45678   51200  102400            123     0     0
            
            parsing_users = False
            for line in stdout.split('\n'):
                line = line.strip()
                
                if not line or line.startswith('***') or line.startswith('Block grace'):
                    continue
                
                if 'Block limits' in line or 'User' in line:
                    parsing_users = True
                    continue
                
                if line.startswith('---'):
                    continue
                
                if parsing_users:
                    parts = line.split()
                    if len(parts) >= 7:
                        try:
                            username = parts[0]
                            used_kb = int(parts[2]) if parts[2].isdigit() else 0
                            soft_kb = int(parts[3]) if parts[3].isdigit() else 0
                            hard_kb = int(parts[4]) if parts[4].isdigit() else 0
                            grace = parts[5] if len(parts) > 5 and not parts[5].isdigit() else ''
                            
                            # Skip system users and users with no quota
                            if username in ['root', 'nobody'] or (soft_kb == 0 and hard_kb == 0):
                                continue
                            
                            quotas.append({
                                'username': username,
                                'used_mb': self._kb_to_mb(used_kb),
                                'soft_limit_mb': self._kb_to_mb(soft_kb),
                                'hard_limit_mb': self._kb_to_mb(hard_kb),
                                'grace': grace,
                                'percentage': self._calculate_percentage(used_kb, hard_kb)
                            })
                        except (ValueError, IndexError):
                            continue
            
            logger.info(f"Retrieved quotas for {len(quotas)} users")
            return quotas
            
        except Exception as e:
            logger.error(f"Failed to get all quotas: {str(e)}")
            return []
    
    def _calculate_percentage(self, used: int, limit: int) -> float:
        """Calculate usage percentage"""
        if limit == 0:
            return 0.0
        return round((used / limit) * 100, 2)
    
    def get_filesystem_usage(self) -> Dict[str, any]:
        """
        Get overall filesystem usage
        
        Returns:
            Dictionary with filesystem usage information
        """
        try:
            # Use df command to get filesystem info
            result = subprocess.run(
                ['df', '-h', self.filesystem],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            lines = result.stdout.strip().split('\n')
            if len(lines) < 2:
                raise QuotaException("Unable to parse df output")
            
            # Parse df output
            # Filesystem      Size  Used Avail Use% Mounted on
            parts = lines[1].split()
            
            usage_info = {
                'filesystem': parts[0],
                'size': parts[1],
                'used': parts[2],
                'available': parts[3],
                'percentage': parts[4],
                'mountpoint': parts[5] if len(parts) > 5 else self.filesystem
            }
            
            logger.info(f"Filesystem usage: {usage_info['percentage']} used")
            return usage_info
            
        except Exception as e:
            logger.error(f"Failed to get filesystem usage: {str(e)}")
            return {
                'filesystem': self.filesystem,
                'error': str(e)
            }
    
    def check_quota_status(self, username: str) -> Dict[str, any]:
        """
        Check if user is over quota
        
        Args:
            username: Username to check
            
        Returns:
            Dictionary with status information
        """
        try:
            quota = self.get_user_quota(username)
            
            status = {
                'username': username,
                'has_quota': quota['hard_limit_mb'] > 0,
                'over_soft': False,
                'over_hard': False,
                'percentage': 0.0,
                'warning': None
            }
            
            if status['has_quota']:
                used = quota['used_mb']
                soft = quota['soft_limit_mb']
                hard = quota['hard_limit_mb']
                
                status['percentage'] = self._calculate_percentage(used, hard) if hard > 0 else 0
                status['over_soft'] = used >= soft
                status['over_hard'] = used >= hard
                
                if status['over_hard']:
                    status['warning'] = 'User has exceeded hard limit - no more writes allowed'
                elif status['over_soft']:
                    status['warning'] = f"User has exceeded soft limit - grace period: {quota.get('grace', 'N/A')}"
                elif status['percentage'] >= 80:
                    status['warning'] = f"User is approaching quota limit ({status['percentage']}%)"
            
            return status
            
        except Exception as e:
            logger.error(f"Failed to check quota status for {username}: {str(e)}")
            return {
                'username': username,
                'error': str(e)
            }
    
    def get_top_users(self, limit: int = 10) -> List[Dict[str, any]]:
        """
        Get top users by disk usage
        
        Args:
            limit: Number of top users to return
            
        Returns:
            List of users sorted by usage
        """
        try:
            all_quotas = self.get_all_quotas()
            
            # Sort by usage descending
            sorted_quotas = sorted(all_quotas, key=lambda x: x['used_mb'], reverse=True)
            
            return sorted_quotas[:limit]
            
        except Exception as e:
            logger.error(f"Failed to get top users: {str(e)}")
            return []
