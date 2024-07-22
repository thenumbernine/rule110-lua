package = "rule110"
version = "dev-1"
source = {
	url = "git+https://github.com/thenumbernine/rule110-lua"
}
description = {
	detailed = "Rule 110 on GPU",
	homepage = "https://github.com/thenumbernine/rule110-lua",
	license = "MIT"
}
dependencies = {
	"lua >= 5.1"
}
build = {
	type = "builtin",
	modules = {
		rule110 = "rule110.lua"
	}
}
