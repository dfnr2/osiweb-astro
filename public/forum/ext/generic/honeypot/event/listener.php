<?php
/**
 * Registration Honeypot Extension
 * Event listener
 */

namespace generic\honeypot\event;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class listener implements EventSubscriberInterface
{
    /** @var \phpbb\request\request */
    protected $request;

    /** @var \phpbb\config\config */
    protected $config;

    /** @var \phpbb\template\template */
    protected $template;

    public function __construct(
        \phpbb\request\request $request,
        \phpbb\config\config $config,
        \phpbb\template\template $template
    ) {
        $this->request = $request;
        $this->config = $config;
        $this->template = $template;
    }

    public static function getSubscribedEvents()
    {
        return [
            'core.ucp_register_data_after'      => 'check_honeypot',
            'core.ucp_register_data_before'     => 'assign_template_vars',
        ];
    }

    /**
     * Assign honeypot config to template variables
     */
    public function assign_template_vars($event)
    {
        if (!$this->config['honeypot_enabled'])
        {
            return;
        }

        $this->template->assign_vars([
            'HONEYPOT_ENABLED'      => true,
            'HONEYPOT_FIELD_NAME'   => $this->config['honeypot_field_name'],
            'HONEYPOT_QUESTION'     => $this->config['honeypot_question'],
            'HONEYPOT_EXPLANATION'  => $this->config['honeypot_explanation'],
        ]);
    }

    /**
     * Check honeypot field - reject if filled
     */
    public function check_honeypot($event)
    {
        if (!$this->config['honeypot_enabled'])
        {
            return;
        }

        $field_name = $this->config['honeypot_field_name'];
        $honeypot = $this->request->variable($field_name, '', true);

        if (!empty(trim($honeypot)))
        {
            $error = $event['error'];
            $error[] = $this->config['honeypot_error_message'];
            $event['error'] = $error;
        }
    }
}
