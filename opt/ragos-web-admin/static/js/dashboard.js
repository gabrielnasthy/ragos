// RAGOS Web Admin - Dashboard JavaScript

$(document).ready(function() {
    let storageChart;
    let topUsersChart;
    
    // Load dashboard data
    function loadDashboard() {
        loadStats();
        loadCharts();
        loadMetrics();
        loadServices();
        loadRecentActivity();
    }
    
    // Load statistics
    function loadStats() {
        // Load user count
        $.ajax({
            url: '/api/users',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    $('#totalUsers').text(response.users.length);
                }
            }
        });
        
        // Load group count
        $.ajax({
            url: '/api/groups',
            method: 'GET',
            success: function(response) {
                if (response.success) {
                    $('#totalGroups').text(response.groups.length);
                }
            }
        });
        
        // Load system metrics
        $.ajax({
            url: '/api/monitoring/system',
            method: 'GET',
            success: function(response) {
                if (response.success && response.metrics) {
                    const disk = response.metrics.disk;
                    $('#diskUsage').text(disk.percent + '%');
                    
                    const load = response.metrics.load_average;
                    $('#systemLoad').text(load['1min'].toFixed(2));
                }
            }
        });
    }
    
    // Load charts
    function loadCharts() {
        // Storage distribution chart
        $.ajax({
            url: '/api/monitoring/storage',
            method: 'GET',
            success: function(response) {
                if (response.success && response.filesystem) {
                    const fs = response.filesystem;
                    
                    // Parse size strings (e.g., "100G" -> GB value)
                    const parseSize = (str) => {
                        const match = str.match(/([\d.]+)([KMGT]?)/);
                        if (!match) return 0;
                        const value = parseFloat(match[1]);
                        const unit = match[2];
                        const multipliers = { 'K': 1/1024/1024, 'M': 1/1024, 'G': 1, 'T': 1024 };
                        return value * (multipliers[unit] || 1);
                    };
                    
                    const used = parseSize(fs.used);
                    const available = parseSize(fs.available);
                    
                    if (storageChart) storageChart.destroy();
                    
                    const ctx = document.getElementById('storageChart').getContext('2d');
                    storageChart = new Chart(ctx, {
                        type: 'doughnut',
                        data: {
                            labels: ['Used', 'Available'],
                            datasets: [{
                                data: [used, available],
                                backgroundColor: ['#e74c3c', '#2ecc71'],
                                borderWidth: 0
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            plugins: {
                                legend: {
                                    position: 'bottom'
                                },
                                title: {
                                    display: true,
                                    text: `Total: ${fs.size}`
                                }
                            }
                        }
                    });
                }
                
                // Top users chart
                if (response.top_users) {
                    const topUsers = response.top_users;
                    
                    if (topUsersChart) topUsersChart.destroy();
                    
                    const ctx2 = document.getElementById('topUsersChart').getContext('2d');
                    topUsersChart = new Chart(ctx2, {
                        type: 'bar',
                        data: {
                            labels: topUsers.map(u => u.username),
                            datasets: [{
                                label: 'Disk Usage (MB)',
                                data: topUsers.map(u => u.used_mb),
                                backgroundColor: '#3498db',
                                borderWidth: 0
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                y: {
                                    beginAtZero: true,
                                    ticks: {
                                        callback: function(value) {
                                            return formatBytes(value * 1024 * 1024);
                                        }
                                    }
                                }
                            },
                            plugins: {
                                legend: {
                                    display: false
                                }
                            }
                        }
                    });
                }
            }
        });
    }
    
    // Load system metrics
    function loadMetrics() {
        $.ajax({
            url: '/api/monitoring/system',
            method: 'GET',
            success: function(response) {
                if (response.success && response.metrics) {
                    const cpu = response.metrics.cpu;
                    const memory = response.metrics.memory;
                    const disk = response.metrics.disk;
                    
                    // Update progress bars
                    $('#cpuBar').css('width', cpu.percent + '%').text(cpu.percent.toFixed(1) + '%');
                    $('#memoryBar').css('width', memory.percent + '%').text(memory.percent.toFixed(1) + '%');
                    $('#diskBar').css('width', disk.percent + '%').text(disk.percent + '%');
                    
                    // Update colors based on thresholds
                    updateProgressColor($('#cpuBar'), cpu.percent);
                    updateProgressColor($('#memoryBar'), memory.percent);
                    updateProgressColor($('#diskBar'), disk.percent);
                }
            }
        });
    }
    
    // Update progress bar color based on percentage
    function updateProgressColor($bar, percent) {
        $bar.removeClass('bg-success bg-warning bg-danger');
        
        if (percent < 60) {
            $bar.addClass('bg-success');
        } else if (percent < 80) {
            $bar.addClass('bg-warning');
        } else {
            $bar.addClass('bg-danger');
        }
    }
    
    // Load services status
    function loadServices() {
        $.ajax({
            url: '/api/monitoring/services',
            method: 'GET',
            success: function(response) {
                if (response.success && response.services) {
                    const container = $('#servicesList');
                    container.empty();
                    
                    response.services.forEach(function(service) {
                        const icon = service.active ? 
                            '<i class="bi bi-check-circle-fill text-success"></i>' : 
                            '<i class="bi bi-x-circle-fill text-danger"></i>';
                        
                        const item = `
                            <div class="d-flex justify-content-between align-items-center mb-2 p-2 border-bottom">
                                <span><strong>${service.name}</strong></span>
                                <span>${icon} ${service.status}</span>
                            </div>
                        `;
                        container.append(item);
                    });
                }
            }
        });
    }
    
    // Load recent activity (admin only)
    function loadRecentActivity() {
        if ($('#activityTable').length === 0) return;
        
        $.ajax({
            url: '/api/monitoring/audit-log?limit=10',
            method: 'GET',
            success: function(response) {
                if (response.success && response.logs) {
                    const tbody = $('#activityTable tbody');
                    tbody.empty();
                    
                    if (response.logs.length === 0) {
                        tbody.append('<tr><td colspan="5" class="text-center">No recent activity</td></tr>');
                        return;
                    }
                    
                    response.logs.forEach(function(log) {
                        const statusBadge = log.status === 'success' ? 
                            '<span class="badge bg-success">Success</span>' : 
                            '<span class="badge bg-danger">Failed</span>';
                        
                        const time = new Date(log.timestamp).toLocaleTimeString();
                        
                        const row = `
                            <tr>
                                <td>${time}</td>
                                <td>${log.username}</td>
                                <td><code>${log.action}</code></td>
                                <td>${log.target || '-'}</td>
                                <td>${statusBadge}</td>
                            </tr>
                        `;
                        tbody.append(row);
                    });
                }
            }
        });
    }
    
    // Initial load
    loadDashboard();
    
    // Auto-refresh every 30 seconds
    setInterval(function() {
        loadMetrics();
        loadServices();
    }, 30000);
});
