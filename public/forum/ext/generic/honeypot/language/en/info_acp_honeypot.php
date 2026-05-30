<?php
/**
 * Registration Honeypot - ACP info language file
 */

if (!defined('IN_PHPBB'))
{
    exit;
}

if (empty($lang) || !is_array($lang))
{
    $lang = [];
}

$lang = array_merge($lang, [
    'ACP_HONEYPOT_TITLE'    => 'Registration Honeypot',
    'ACP_HONEYPOT_SETTINGS' => 'Honeypot Settings',
]);
