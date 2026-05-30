<?php
namespace generic\honeypot\acp;

class main_module
{
    public $page_title;
    public $tpl_name;
    public $u_action;

    public function main($id, $mode)
    {
        global $config, $request, $template, $language, $phpbb_container;

        $language->add_lang('common', 'generic/honeypot');

        $this->tpl_name = 'acp_honeypot_settings';
        $this->page_title = $language->lang('ACP_HONEYPOT_TITLE');

        add_form_key('generic_honeypot_settings');

        if ($request->is_set_post('submit'))
        {
            if (!check_form_key('generic_honeypot_settings'))
            {
                trigger_error('FORM_INVALID', E_USER_WARNING);
            }

            $config->set('honeypot_enabled', $request->variable('honeypot_enabled', 0));
            $config->set('honeypot_field_name', $request->variable('honeypot_field_name', 'website_url'));
            $config->set('honeypot_question', $request->variable('honeypot_question', '', true));
            $config->set('honeypot_explanation', $request->variable('honeypot_explanation', '', true));
            $config->set('honeypot_error_message', $request->variable('honeypot_error_message', '', true));

            trigger_error($language->lang('ACP_HONEYPOT_SAVED') . adm_back_link($this->u_action));
        }

        $template->assign_vars([
            'U_ACTION'              => $this->u_action,
            'HONEYPOT_ENABLED'      => $config['honeypot_enabled'],
            'HONEYPOT_FIELD_NAME'   => $config['honeypot_field_name'],
            'HONEYPOT_QUESTION'     => $config['honeypot_question'],
            'HONEYPOT_EXPLANATION'  => $config['honeypot_explanation'],
            'HONEYPOT_ERROR_MESSAGE'=> $config['honeypot_error_message'],
        ]);
    }
}
