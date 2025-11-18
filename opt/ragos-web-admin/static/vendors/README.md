# Vendor Libraries

This directory is for vendor-specific libraries and assets if you prefer to host them locally instead of using CDN.

## Using CDN (Current Configuration)

The application currently uses CDN links for:
- Bootstrap 5.3.2
- Bootstrap Icons 1.11.1
- jQuery 3.7.1
- DataTables 1.13.7
- Chart.js 4.4.0

## Using Local Files (Optional)

To use local copies instead of CDN:

1. Download the libraries:
   ```bash
   # Bootstrap
   wget https://github.com/twbs/bootstrap/releases/download/v5.3.2/bootstrap-5.3.2-dist.zip
   unzip bootstrap-5.3.2-dist.zip -d vendors/bootstrap
   
   # jQuery
   wget https://code.jquery.com/jquery-3.7.1.min.js -P vendors/jquery/
   
   # DataTables
   wget https://cdn.datatables.net/1.13.7/js/jquery.dataTables.min.js -P vendors/datatables/
   wget https://cdn.datatables.net/1.13.7/css/dataTables.bootstrap5.min.css -P vendors/datatables/
   
   # Chart.js
   wget https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js -P vendors/chartjs/
   ```

2. Update base.html to use local paths instead of CDN URLs

## Current Dependencies

- **Bootstrap 5**: CSS framework for responsive design
- **Bootstrap Icons**: Icon library
- **jQuery**: JavaScript library for DOM manipulation
- **DataTables**: Advanced table plugin
- **Chart.js**: Data visualization library

## Notes

- CDN is recommended for better performance and caching
- Local files are useful for air-gapped or offline environments
- Keep libraries updated for security patches
