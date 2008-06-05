# init.pp
# passwd file distribution

import "*.pp"

class fileauth {
	include "fileauth::$ccbp_osfam"
}

