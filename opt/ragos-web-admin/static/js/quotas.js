// RAGOS Web Admin - Quotas Management JavaScript

$(document).ready(function() {
    let quotasTable;
    const isAdmin = $('button[data-bs-target="#setQuotaModal"]').length > 0;
    
    // Load quotas
    function loadQuotas() {
        $.ajax({
            url: '/api/quotas',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    const tbody = $('#quotasTable tbody');
                    tbody.empty();
                    
                    if (response.quotas.length === 0) {
                        tbody.append('<tr><td colspan="7" class="text-center">No quotas configured</td></tr>');
                        return;
                    }
                    
                    response.quotas.forEach(function(quota) {
                        const percentage = quota.percentage || 0;
                        
                        let statusBadge = '<span class="badge bg-success">OK</span>';
                        if (percentage >= 100) {
                            statusBadge = '<span class="badge bg-danger">Over Limit</span>';
                        } else if (percentage >= 80) {
                            statusBadge = '<span class="badge bg-warning">Warning</span>';
                        }
                        
                        let progressClass = 'bg-success';
                        if (percentage >= 80) progressClass = 'bg-danger';
                        else if (percentage >= 60) progressClass = 'bg-warning';
                        
                        const row = `
                            <tr>
                                <td><strong>${quota.username}</strong></td>
                                <td>${quota.used_mb} MB</td>
                                <td>${quota.soft_limit_mb} MB</td>
                                <td>${quota.hard_limit_mb} MB</td>
                                <td>
                                    <div class="progress" style="height: 20px;">
                                        <div class="progress-bar ${progressClass}" role="progressbar" 
                                             style="width: ${Math.min(percentage, 100)}%">
                                            ${percentage.toFixed(1)}%
                                        </div>
                                    </div>
                                </td>
                                <td>${statusBadge}</td>
                                <td>
                                    ${isAdmin ? `
                                    <button class="btn btn-sm btn-primary" onclick="editQuota('${quota.username}', ${quota.soft_limit_mb}, ${quota.hard_limit_mb})">
                                        <i class="bi bi-pencil"></i> Edit
                                    </button>
                                    ` : ''}
                                </td>
                            </tr>
                        `;
                        tbody.append(row);
                    });
                    
                    // Initialize DataTable
                    if (quotasTable) {
                        quotasTable.destroy();
                    }
                    quotasTable = $('#quotasTable').DataTable({
                        pageLength: 25,
                        order: [[4, 'desc']] // Sort by usage percentage
                    });
                }
            },
            error: function(xhr) {
                showToast('Failed to load quotas', 'danger');
            }
        });
    }
    
    // Load users for dropdown
    function loadUsersDropdown() {
        $.ajax({
            url: '/api/users',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    const select = $('#quotaUsername');
                    select.empty();
                    select.append('<option value="">Select user...</option>');
                    
                    response.users.forEach(function(user) {
                        select.append(`<option value="${user.username}">${user.username}</option>`);
                    });
                }
            }
        });
    }
    
    // Load quota policies
    function loadPolicies() {
        $.ajax({
            url: '/api/quota-policies',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    // Update policy select
                    const select = $('#policySelect');
                    select.empty();
                    select.append('<option value="">Select a policy...</option>');
                    
                    response.policies.forEach(function(policy) {
                        select.append(`<option value="${policy.id}" data-soft="${policy.soft_limit}" data-hard="${policy.hard_limit}">
                            ${policy.policy_name} (${policy.soft_limit}MB / ${policy.hard_limit}MB)
                        </option>`);
                    });
                    
                    // Update policies table
                    const tbody = $('#policiesTableBody');
                    tbody.empty();
                    
                    if (response.policies.length === 0) {
                        tbody.append('<tr><td colspan="4" class="text-center">No policies defined</td></tr>');
                        return;
                    }
                    
                    response.policies.forEach(function(policy) {
                        const row = `
                            <tr>
                                <td><strong>${policy.policy_name}</strong> ${policy.is_default ? '<span class="badge bg-primary">Default</span>' : ''}</td>
                                <td>${policy.soft_limit} MB</td>
                                <td>${policy.hard_limit} MB</td>
                                <td>${policy.description || '-'}</td>
                            </tr>
                        `;
                        tbody.append(row);
                    });
                }
            }
        });
    }
    
    // Policy select handler
    $('#policySelect').on('change', function() {
        const selected = $(this).find('option:selected');
        if (selected.val()) {
            $('input[name="soft_limit"]').val(selected.data('soft'));
            $('input[name="hard_limit"]').val(selected.data('hard'));
        }
    });
    
    // Set quota
    $('#setQuotaForm').on('submit', function(e) {
        e.preventDefault();
        
        const username = $('#quotaUsername').val();
        const softLimit = parseInt($('input[name="soft_limit"]').val());
        const hardLimit = parseInt($('input[name="hard_limit"]').val());
        
        if (!username) {
            showToast('Please select a user', 'warning');
            return;
        }
        
        if (softLimit > hardLimit) {
            showToast('Soft limit cannot exceed hard limit', 'warning');
            return;
        }
        
        $.ajax({
            url: `/api/quotas/${username}`,
            method: 'POST',
            contentType: 'application/json',
            data: JSON.stringify({
                soft_limit: softLimit,
                hard_limit: hardLimit
            }),
            success: function(response) {
                if (response.success) {
                    showToast(response.message, 'success');
                    $('#setQuotaModal').modal('hide');
                    $('#setQuotaForm')[0].reset();
                    $('#quotaUsername').prop('disabled', false);
                    loadQuotas();
                }
            },
            error: function(xhr) {
                showToast(xhr.responseJSON?.message || 'Failed to set quota', 'danger');
            }
        });
    });
    
    // Edit quota
    window.editQuota = function(username, softLimit, hardLimit) {
        $('#quotaUsername').val(username).prop('disabled', true);
        $('input[name="soft_limit"]').val(softLimit);
        $('input[name="hard_limit"]').val(hardLimit);
        $('#setQuotaModal').modal('show');
    };
    
    // Reset modal on close
    $('#setQuotaModal').on('hidden.bs.modal', function() {
        $('#setQuotaForm')[0].reset();
        $('#quotaUsername').prop('disabled', false);
    });
    
    // Initial load
    loadQuotas();
    loadUsersDropdown();
    loadPolicies();
    
    // Auto-refresh every 30 seconds
    setInterval(loadQuotas, 30000);
});
