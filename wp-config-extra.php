<?php

define('WP_ENVIRONMENT_TYPE', getenv('WORDPRESS_ENV') ?: 'production');

define('FORCE_SSL_ADMIN', true);

if (
    isset($_SERVER['HTTP_X_FORWARDED_PROTO']) &&
    $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https'
) {
    $_SERVER['HTTPS'] = 'on';
}

if (!defined('WP_CACHE')) {
    define('WP_CACHE', true);
}

define('DISALLOW_FILE_EDIT', true);

if (getenv('WORDPRESS_REDIS_HOST')) {
    define('WP_REDIS_HOST', getenv('WORDPRESS_REDIS_HOST'));
    define('WP_REDIS_PORT', (int) (getenv('WORDPRESS_REDIS_PORT') ?: 6379));
    define('WP_REDIS_PREFIX', getenv('WORDPRESS_REDIS_PREFIX') ?: 'wp:');
}

foreach ([
    'WORDPRESS_AUTH_KEY' => 'AUTH_KEY',
    'WORDPRESS_SECURE_AUTH_KEY' => 'SECURE_AUTH_KEY',
    'WORDPRESS_LOGGED_IN_KEY' => 'LOGGED_IN_KEY',
    'WORDPRESS_NONCE_KEY' => 'NONCE_KEY',
    'WORDPRESS_AUTH_SALT' => 'AUTH_SALT',
    'WORDPRESS_SECURE_AUTH_SALT' => 'SECURE_AUTH_SALT',
    'WORDPRESS_LOGGED_IN_SALT' => 'LOGGED_IN_SALT',
    'WORDPRESS_NONCE_SALT' => 'NONCE_SALT',
] as $env => $constant) {
    $value = getenv($env);
    if ($value && !defined($constant)) {
        define($constant, $value);
    }
}