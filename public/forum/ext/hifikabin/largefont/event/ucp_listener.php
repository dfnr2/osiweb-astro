<?php
/**
 *
 * @package Large Font
 * @copyright (c) 2014 HiFiKabin
 * @license http://opensource.org/licenses/gpl-2.0.php GNU General Public License v2
 *
 */

namespace hifikabin\largefont\event;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Event listener for UCP related actions
 */
class ucp_listener implements EventSubscriberInterface
{
	/** @var \phpbb\request\request */
	protected $request;

	/** @var \phpbb\template\template */
	protected $template;

	/** @var \phpbb\user */
	protected $user;

	/** @var \phpbb\language */
	protected $language;

	public function __construct(\phpbb\request\request $request, \phpbb\template\template $template, \phpbb\user $user, \phpbb\language\language $language)
	{
		$this->request		= $request;
		$this->template		= $template;
		$this->user			= $user;
		$this->language		= $language;
	}

	/**
	 * Assign functions defined in this class to event listeners in the core
	 *
	 * @return array
	 * @static
	 * @access public
	 */
	static public function getSubscribedEvents()
	{
		return array(
			'core.user_setup'						=> 'load_lang',
			'core.ucp_prefs_personal_data'			=> 'ucp_prefs_get_data',
			'core.ucp_prefs_personal_update_data'	=> 'ucp_prefs_set_data'
		);
	}

	/**
	 * Load language during user set up.
	 *
	 * @event  core.user_setup
	 * @return void
	 * @access public
	 */
	public function load_lang()
	{
		$this->language->add_lang('font_ucp', 'hifikabin/largefont');
	}

	/**
	 * Get user's option and display it in UCP Prefs View page
	 *
	 * @param object $event The event object
	 * @return null
	 * @access public
	 */
	public function ucp_prefs_get_data($event)
	{
		// Request the user option vars and add them to the data array
		$event['data'] = array_merge($event['data'], array(
			'font'				=> $this->request->variable('font', (int) $this->user->data['user_font']),
			'bold'				=> $this->request->variable('bold', (int) $this->user->data['user_font_bold']),
			'size'				=> $this->request->variable('size', (int) $this->user->data['user_font_size']),
			'mobile_font'		=> $this->request->variable('mobile_font', (int) $this->user->data['user_mobile_font']),
			'mobile_size'		=> $this->request->variable('mobile_size', (int) $this->user->data['user_mobile_font_size'])
		));

		// Output the data vars to the template (except on form submit)
		if (!$event['submit'])
		{

			$this->template->assign_vars(array(
				'S_USER_FONT'				=> $event['data']['font'],
				'S_USER_FONT_BOLD'			=> $event['data']['bold'],
				'S_USER_FONT_SIZE'			=> $event['data']['size'],
				'S_USER_MOBILE_FONT'		=> $event['data']['mobile_font'],
				'S_USER_MOBILE_FONT_SIZE'	=> $event['data']['mobile_size']
			));
		}
	}

	public function ucp_prefs_set_data($event)
	{
		$event['sql_ary'] = array_merge($event['sql_ary'], array(
			'user_font'					=> $event['data']['font'],
			'user_font_bold'			=> $event['data']['bold'],
			'user_font_size'			=> $event['data']['size'],
			'user_mobile_font'			=> $event['data']['mobile_font'],
			'user_mobile_font_size'		=> $event['data']['mobile_size']
		));
	}
}
