<?php

return [

    'default' => env('DB_CONNECTION', 'mysql'),

    'connections' => [

        'mysql' => [
            'driver' => 'mysql',

            'write' => [
                'host' => [env('DB_HOST', '127.0.0.1')],
            ],
            'read' => [
                'host' => [env('DB_READ_HOST') ?: env('DB_HOST', '127.0.0.1')],
            ],

            'sticky' => true,

            'port' => env('DB_PORT', '3306'),
            'database' => env('DB_DATABASE', 'cloudpulse'),
            'username' => env('DB_USERNAME', 'cloudpulse'),
            'password' => env('DB_PASSWORD'),
            'unix_socket' => '',
            'charset' => 'utf8mb4',
            'collation' => 'utf8mb4_unicode_ci',
            'prefix' => '',
            'prefix_indexes' => true,
            'strict' => true,
            'engine' => null,

            'options' => [
                PDO::ATTR_TIMEOUT => (int) env('DB_TIMEOUT', 3),
            ],
        ],

        'sqlite' => [
            'driver' => 'sqlite',
            'database' => env('DB_DATABASE', database_path('database.sqlite')),
            'prefix' => '',
            'foreign_key_constraints' => true,
        ],

    ],

];
