<?php
namespace generic\honeypot\acp;

class main_info
{
    public function module()
    {
        return [
            'filename'  => '\generic\honeypot\acp\main_module',
            'title'     => 'ACP_HONEYPOT_TITLE',
            'modes'     => [
                'settings'  => [
                    'title' => 'ACP_HONEYPOT_SETTINGS',
                    'auth'  => 'ext_generic/honeypot && acl_a_board',
                    'cat'   => ['ACP_HONEYPOT_TITLE'],
                ],
            ],
        ];
    }
}
