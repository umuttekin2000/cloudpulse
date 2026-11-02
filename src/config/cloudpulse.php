<?php


return [

    
    'version' => env('APP_VERSION', 'dev'),
    'commit' => env('APP_COMMIT_SHA', 'local'),

    
    'disk' => env('CLOUDPULSE_DISK', 's3'),

   
    'max_upload_kb' => (int) env('CLOUDPULSE_MAX_UPLOAD_KB', 10240),
    'allowed_extensions' => array_values(array_filter(array_map(
        'trim',
        explode(',', (string) env('CLOUDPULSE_ALLOWED_EXTENSIONS', 'jpg,jpeg,png,pdf,txt,csv,zip')),
    ))),
    'uploads_per_minute' => (int) env('CLOUDPULSE_UPLOADS_PER_MINUTE', 20),

    
    'status_poll_seconds' => (int) env('CLOUDPULSE_STATUS_POLL_SECONDS', 10),

];
