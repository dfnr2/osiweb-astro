<?php
/**
*
* @package Large Font
* @copyright (c) 2014 HiFiKabin
* @license http://opensource.org/licenses/gpl-2.0.php GNU General Public License v2
*
*/

namespace hifikabin\largefont\migrations\v1x;

class release_1_0_1_data extends \phpbb\db\migration\migration
{
	static public function depends_on()
	{
		return array('\hifikabin\largefont\migrations\v1x\release_1_0_0_data');
	}

	public function update_data()
	{
		return array(
			array('config.remove', array('font_version', '')),
		);
	}
}
