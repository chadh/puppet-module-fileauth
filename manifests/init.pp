# init.pp
# passwd file distribution

import "*.pp"

class fileauth::server {
	include "fileauth::server::$ccbp_osfam"
}

class fileauth::client {
	include "fileauth::client::$ccbp_osfam"
}

