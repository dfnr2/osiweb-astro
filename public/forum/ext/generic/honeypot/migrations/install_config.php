<?php
namespace generic\honeypot\migrations;

class install_config extends \phpbb\db\migration\migration
{
    public function effectively_installed()
    {
        return $this->config->offsetExists('honeypot_enabled');
    }

    public static function depends_on()
    {
        return ['\phpbb\db\migration\data\v320\v320'];
    }

    public function update_data()
    {
        return [
            ['config.add', ['honeypot_enabled', 1]],
            ['config.add', ['honeypot_field_name', 'website_url']],
            ['config.add', ['honeypot_question', 'Website URL']],
            ['config.add', ['honeypot_explanation', 'Leave this field empty']],
            ['config.add', ['honeypot_error_message', 'Registration could not be completed. Please try again later.']],

            ['module.add', [
                'acp',
                'ACP_CAT_DOT_MODS',
                'ACP_HONEYPOT_TITLE'
            ]],
            ['module.add', [
                'acp',
                'ACP_HONEYPOT_TITLE',
                [
                    'module_basename'   => '\generic\honeypot\acp\main_module',
                    'modes'             => ['settings'],
                ],
            ]],
        ];
    }
}
