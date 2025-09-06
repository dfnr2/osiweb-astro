<?php
/**
*
* @package Large Font
* @copyright (c) 2014 HiFiKabin
* @license http://opensource.org/licenses/gpl-2.0.php GNU General Public License v2
*
*/

namespace hifikabin\largefont\migrations\v1x;

class release_1_0_0_data extends \phpbb\db\migration\migration
{
	public function effectively_installed()
	{
		return isset($this->config['font_version']) && version_compare($this->config['font_version'], '1.0.0', '>=');
	}

	static public function depends_on()
	{
		return array('\phpbb\db\migration\data\v310\dev');
	}

	public function update_data()
	{
		return array(
			array('config.add', array('font_version', '1.0.0')),
		);
	}

	public function revert_data()
	{
		return array(
			array('config.remove', array('font_version')),
		);
	}
}
