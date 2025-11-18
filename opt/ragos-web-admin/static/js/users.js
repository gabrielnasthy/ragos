// RAGOS Web Admin - Users Management JavaScript

$(document).ready(function() {
    let usersTable;
    const isAdmin = $('button[data-bs-target="#createUserModal"]').length > 0;
    
    // Load users
    function loadUsers() {
        $.ajax({
            url: '/api/users',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    const tbody = $('#usersTable tbody');
                    tbody.empty();
                    
                    if (response.users.length === 0) {
                        tbody.append('<tr><td colspan="6" class="text-center">No users found</td></tr>');
                        return;
                    }
                    
                    response.users.forEach(function(user) {
                        const quota = user.quota || {};
                        const used = quota.used_mb || 0;
                        const hardLimit = quota.hard_limit_mb || 0;
                        const percentage = hardLimit > 0 ? ((used / hardLimit) * 100).toFixed(1) : 0;
                        
                        let progressClass = 'bg-success';
                        if (percentage >= 80) progressClass = 'bg-danger';
                        else if (percentage >= 60) progressClass = 'bg-warning';
                        
                        const statusBadge = user.enabled !== false ? 
                            '<span class="badge bg-success">Active</span>' : 
                            '<span class="badge bg-secondary">Disabled</span>';
                        
                        const row = `
                            <tr>
                                <td><strong>${user.username}</strong></td>
                                <td>${used} MB</td>
                                <td>${hardLimit} MB</td>
                                <td>
                                    <div class="progress" style="height: 20px;">
                                        <div class="progress-bar ${progressClass}" role="progressbar" 
                                             style="width: ${percentage}%" aria-valuenow="${percentage}" 
                                             aria-valuemin="0" aria-valuemax="100">
                                            ${percentage}%
                                        </div>
                                    </div>
                                </td>
                                <td>${statusBadge}</td>
                                <td>
                                    <button class="btn btn-sm btn-info" onclick="viewUser('${user.username}')">
                                        <i class="bi bi-eye"></i> View
                                    </button>
                                    ${isAdmin ? `
                                    <button class="btn btn-sm btn-warning" onclick="resetPassword('${user.username}')">
                                        <i class="bi bi-key"></i> Reset
                                    </button>
                                    ${user.username !== 'administrator' ? `
                                    <button class="btn btn-sm btn-danger" onclick="deleteUser('${user.username}')">
                                        <i class="bi bi-trash"></i> Delete
                                    </button>
                                    ` : ''}
                                    ` : ''}
                                </td>
                            </tr>
                        `;
                        tbody.append(row);
                    });
                    
                    // Initialize DataTable
                    if (usersTable) {
                        usersTable.destroy();
                    }
                    usersTable = $('#usersTable').DataTable({
                        pageLength: 25,
                        order: [[0, 'asc']]
                    });
                }
            },
            error: function(xhr) {
                showToast('Failed to load users', 'danger');
            }
        });
    }
    
    // Create user
    $('#createUserForm').on('submit', function(e) {
        e.preventDefault();
        
        const formData = {
            username: $('input[name="username"]').val(),
            password: $('input[name="password"]').val(),
            given_name: $('input[name="given_name"]').val(),
            surname: $('input[name="surname"]').val(),
            mail: $('input[name="mail"]').val(),
            must_change_password: $('input[name="must_change_password"]').is(':checked')
        };
        
        $.ajax({
            url: '/api/users',
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify(formData),
            success: function(response) {
                if (response.success) {
                    showToast(response.message, 'success');
                    $('#createUserModal').modal('hide');
                    $('#createUserForm')[0].reset();
                    loadUsers();
                }
            },
            error: function(xhr) {
                showToast(xhr.responseJSON?.message || 'Failed to create user', 'danger');
            }
        });
    });
    
    // View user
    window.viewUser = function(username) {
        $('#editUsername').text(username);
        $('#editUserModal').modal('show');
        
        // Load user info
        $.ajax({
            url: `/api/users/${username}`,
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    const user = response.user;
                    const quota = response.quota;
                    const groups = response.groups;
                    
                    // User info tab
                    let infoHtml = '<dl class="row">';
                    for (const [key, value] of Object.entries(user)) {
                        if (key !== 'username') {
                            infoHtml += `
                                <dt class="col-sm-4">${key}</dt>
                                <dd class="col-sm-8">${value || '-'}</dd>
                            `;
                        }
                    }
                    infoHtml += '</dl>';
                    $('#userInfo').html(infoHtml);
                    
                    // Quota tab
                    const quotaPercent = quota.hard_limit_mb > 0 ? 
                        ((quota.used_mb / quota.hard_limit_mb) * 100).toFixed(1) : 0;
                    
                    const quotaHtml = `
                        <div class="mb-3">
                            <h6>Disk Usage</h6>
                            <div class="progress" style="height: 30px;">
                                <div class="progress-bar ${quotaPercent >= 80 ? 'bg-danger' : quotaPercent >= 60 ? 'bg-warning' : 'bg-success'}" 
                                     style="width: ${quotaPercent}%">
                                    ${quotaPercent}%
                                </div>
                            </div>
                            <small class="text-muted">
                                ${quota.used_mb} MB used of ${quota.hard_limit_mb} MB (Soft: ${quota.soft_limit_mb} MB)
                            </small>
                        </div>
                        ${isAdmin ? `
                        <div class="mb-3">
                            <button class="btn btn-primary" onclick="editQuota('${username}', ${quota.soft_limit_mb}, ${quota.hard_limit_mb})">
                                <i class="bi bi-pencil"></i> Edit Quota
                            </button>
                        </div>
                        ` : ''}
                    `;
                    $('#userQuota').html(quotaHtml);
                    
                    // Groups tab
                    let groupsHtml = '<div class="list-group">';
                    if (groups.length === 0) {
                        groupsHtml += '<div class="list-group-item">No group memberships</div>';
                    } else {
                        groups.forEach(function(group) {
                            groupsHtml += `
                                <div class="list-group-item">
                                    <i class="bi bi-collection"></i> ${group}
                                </div>
                            `;
                        });
                    }
                    groupsHtml += '</div>';
                    $('#userGroups').html(groupsHtml);
                }
            },
            error: function(xhr) {
                showToast('Failed to load user details', 'danger');
            }
        });
    };
    
    // Reset password
    window.resetPassword = function(username) {
        $('#resetUsername').text(username);
        $('#resetUsernameInput').val(username);
        $('#resetPasswordModal').modal('show');
    };
    
    $('#resetPasswordForm').on('submit', function(e) {
        e.preventDefault();
        
        const username = $('#resetUsernameInput').val();
        const formData = {
            password: $('input[name="password"]').val(),
            must_change: $('input[name="must_change"]').is(':checked')
        };
        
        $.ajax({
            url: `/api/users/${username}/reset-password`,
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify(formData),
            success: function(response) {
                if (response.success) {
                    showToast(response.message, 'success');
                    $('#resetPasswordModal').modal('hide');
                    $('#resetPasswordForm')[0].reset();
                }
            },
            error: function(xhr) {
                showToast(xhr.responseJSON?.message || 'Failed to reset password', 'danger');
            }
        });
    });
    
    // Delete user
    window.deleteUser = function(username) {
        if (!confirm(`Delete user "${username}"? This action cannot be undone and will remove all user data.`)) {
            return;
        }
        
        $.ajax({
            url: `/api/users/${username}`,
            method: 'DELETE',
            success: function(response) {
                if (response.success) {
                    showToast(response.message, 'success');
                    loadUsers();
                }
            },
            error: function(xhr) {
                showToast(xhr.responseJSON?.message || 'Failed to delete user', 'danger');
            }
        });
    };
    
    // Edit quota
    window.editQuota = function(username, softLimit, hardLimit) {
        $('#editUserModal').modal('hide');
        
        // Show set quota modal with pre-filled values
        $('#quotaUsername').val(username).prop('disabled', true);
        $('input[name="soft_limit"]').val(softLimit);
        $('input[name="hard_limit"]').val(hardLimit);
        $('#setQuotaModal').modal('show');
    };
    
    // Initial load
    loadUsers();
});
