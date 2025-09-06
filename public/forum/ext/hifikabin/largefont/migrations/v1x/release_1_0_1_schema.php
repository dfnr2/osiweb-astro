<?php
/**
*
* @package Large Font
* @copyright (c) 2014 HiFiKabin
* @license http://opensource.org/licenses/gpl-2.0.php GNU General Public License v2
*
*/

namespace hifikabin\largefont\migrations\v1x;

class release_1_0_1_schema extends \phpbb\db\migration\migration
{
	static public function depends_on()
	{
		return array('\hifikabin\largefont\migrations\v1x\release_1_0_0_schema');
	}

	public function effectively_installed()
	{
		return $this->db_tools->sql_column_exists($this->table_prefix . 'users', 'user_font_size');
	}

	public function update_schema()
	{
		return array(
			'add_columns'	=> array(
				$this->table_prefix . 'users' => array(
					'user_font_size' => array('UINT', '104'),
				),
			),
		);
	}

	public function revert_schema()
	{
		return array(
			'drop_columns'	=> array(
				$this->table_prefix . 'users' => array(
					'user_font_size',
				),
			),
		);
	}
}
