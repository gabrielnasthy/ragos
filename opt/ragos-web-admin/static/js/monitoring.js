// RAGOS Web Admin - Monitoring JavaScript

$(document).ready(function() {
    let topUsersChart;
    let refreshInterval;
    let countdown = 5;
    
    // Load monitoring data
    function loadMonitoring() {
        loadSystemMetrics();
        loadServices();
        loadStorage();
        loadTopUsers();
    }
    
    // Load system metrics
    function loadSystemMetrics() {
        $.ajax({
            url: '/api/monitoring/system',
            method: 'GET',
            success: function(response) {
                if (response.success && response.metrics) {
                    const cpu = response.metrics.cpu;
                    const memory = response.metrics.memory;
                    const disk = response.metrics.disk;
                    const load = response.metrics.load_average;
                    
                    // Update CPU
                    $('#cpuUsage').text(cpu.percent.toFixed(1) + '%');
                    $('#cpuProgressBar').css('width', cpu.percent + '%');
                    updateColor('#cpuProgressBar', cpu.percent);
                    
                    // Update Memory
                    const memoryPercent = memory.percent;
                    $('#memoryUsage').text(memoryPercent.toFixed(1) + '%');
                    $('#memoryProgressBar').css('width', memoryPercent + '%');
                    updateColor('#memoryProgressBar', memoryPercent);
                    
                    // Update Disk
                    $('#diskUsage').text(disk.percent + '%');
                    $('#diskProgressBar').css('width', disk.percent + '%');
                    updateColor('#diskProgressBar', disk.percent);
                    
                    // Update Load Average
                    $('#loadAverage').text(`${load['1min'].toFixed(2)} / ${load['5min'].toFixed(2)} / ${load['15min'].toFixed(2)}`);
                }
            },
            error: function(xhr) {
                console.error('Failed to load system metrics');
            }
        });
    }
    
    // Update progress bar color
    function updateColor(selector, percent) {
        const $bar = $(selector);
        $bar.removeClass('bg-success bg-warning bg-danger bg-info');
        
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
                    const container = $('#servicesStatus');
                    container.empty();
                    
                    response.services.forEach(function(service) {
                        const statusIcon = service.active ? 
                            '<i class="bi bi-check-circle-fill text-success fs-5"></i>' : 
                            '<i class="bi bi-x-circle-fill text-danger fs-5"></i>';
                        
                        const statusText = service.active ? 
                            '<span class="badge bg-success">Running</span>' : 
                            '<span class="badge bg-danger">Stopped</span>';
                        
                        const item = `
                            <div class="d-flex justify-content-between align-items-center mb-3 p-2 border-bottom">
                                <div>
                                    ${statusIcon}
                                    <strong class="ms-2">${service.name}</strong>
                                </div>
                                ${statusText}
                            </div>
                        `;
                        container.append(item);
                    });
                }
            },
            error: function(xhr) {
                console.error('Failed to load services');
            }
        });
    }
    
    // Load storage status
    function loadStorage() {
        $.ajax({
            url: '/api/monitoring/storage',
            method: 'GET',
            success: function(response) {
                if (response.success && response.filesystem) {
                    const fs = response.filesystem;
                    
                    const html = `
                        <div class="mb-3">
                            <h6>Filesystem: ${fs.filesystem}</h6>
                            <div class="progress" style="height: 30px;">
                                <div class="progress-bar ${parseFloat(fs.percentage) >= 80 ? 'bg-danger' : parseFloat(fs.percentage) >= 60 ? 'bg-warning' : 'bg-success'}" 
                                     style="width: ${fs.percentage}">
                                    ${fs.percentage}
                                </div>
                            </div>
                            <div class="mt-2">
                                <div class="row text-center">
                                    <div class="col-4">
                                        <small class="text-muted">Total</small>
                                        <div><strong>${fs.size}</strong></div>
                                    </div>
                                    <div class="col-4">
                                        <small class="text-muted">Used</small>
                                        <div><strong>${fs.used}</strong></div>
                                    </div>
                                    <div class="col-4">
                                        <small class="text-muted">Available</small>
                                        <div><strong>${fs.available}</strong></div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    `;
                    $('#storageStatus').html(html);
                }
            },
            error: function(xhr) {
                console.error('Failed to load storage');
            }
        });
    }
    
    // Load top users
    function loadTopUsers() {
        $.ajax({
            url: '/api/monitoring/storage',
            method: 'GET',
            success: function(response) {
                if (response.success && response.top_users) {
                    const topUsers = response.top_users;
                    
                    if (topUsersChart) {
                        topUsersChart.destroy();
                    }
                    
                    const ctx = document.getElementById('topUsersChart').getContext('2d');
                    topUsersChart = new Chart(ctx, {
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
                            indexAxis: 'y',
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                x: {
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
                                },
                                tooltip: {
                                    callbacks: {
                                        label: function(context) {
                                            return formatBytes(context.parsed.x * 1024 * 1024);
                                        }
                                    }
                                }
                            }
                        }
                    });
                }
            },
            error: function(xhr) {
                console.error('Failed to load top users');
            }
        });
    }
    
    // Countdown timer
    function startCountdown() {
        countdown = 5;
        $('#refreshCounter').text(countdown);
        
        if (refreshInterval) {
            clearInterval(refreshInterval);
        }
        
        refreshInterval = setInterval(function() {
            countdown--;
            $('#refreshCounter').text(countdown);
            
            if (countdown <= 0) {
                countdown = 5;
                loadMonitoring();
            }
        }, 1000);
    }
    
    // Initial load
    loadMonitoring();
    startCountdown();
    
    // Cleanup on page unload
    $(window).on('beforeunload', function() {
        if (refreshInterval) {
            clearInterval(refreshInterval);
        }
    });
});
