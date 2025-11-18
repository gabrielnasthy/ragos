# RAGOS Logo Placeholder

This directory should contain the RAGOS logo image (logo.png).

For now, the application uses Bootstrap Icons for branding. To add a custom logo:

1. Add your logo image as `logo.png` (recommended size: 200x200px)
2. Update `templates/base.html` to use the logo:

```html
<div class="sidebar-header p-3">
    <img src="{{ url_for('static', filename='img/logo.png') }}" alt="RAGOS" style="height: 40px;">
    <h4 class="d-inline ms-2">RAGOS Admin</h4>
    <small class="text-muted d-block">v1.0.0</small>
</div>
```

Supported formats: PNG, SVG, JPG
