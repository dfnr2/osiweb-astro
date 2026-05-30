<?php
/**
 * Registration Honeypot - Language file
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
    'ACP_HONEYPOT_TITLE'            => 'Registration Honeypot',
    'ACP_HONEYPOT_SETTINGS'         => 'Honeypot Settings',
    'ACP_HONEYPOT_SAVED'            => 'Honeypot settings saved successfully.',

    'ACP_HONEYPOT_ENABLED'          => 'Enable honeypot',
    'ACP_HONEYPOT_ENABLED_EXPLAIN'  => 'When enabled, a hidden field will be added to the registration form. If filled in (by bots), registration will be rejected.',

    'ACP_HONEYPOT_FIELD_NAME'       => 'Field name',
    'ACP_HONEYPOT_FIELD_NAME_EXPLAIN' => 'The HTML input field name. Use something tempting to bots like "website_url", "company", "phone", "fax". Avoid obvious names like "honeypot".',

    'ACP_HONEYPOT_QUESTION'         => 'Field label',
    'ACP_HONEYPOT_QUESTION_EXPLAIN' => 'The visible label for the field in the HTML. Bots will see this when parsing the form.',

    'ACP_HONEYPOT_EXPLANATION'      => 'Field explanation / Bot bait',
    'ACP_HONEYPOT_EXPLANATION_EXPLAIN' => 'Additional text near the field. Use this to bait bots into filling in a specific answer. Example: "Humans know the answer is 42" will trick bots into entering "42".',

    'ACP_HONEYPOT_ERROR_MESSAGE'    => 'Error message',
    'ACP_HONEYPOT_ERROR_MESSAGE_EXPLAIN' => 'Message shown when registration is rejected. Keep it generic to not reveal the honeypot.',
]);
