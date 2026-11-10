#!/bin/sh
# Runs every scenario of the test script, and stops at the first that fails.
# Needs Lua 5.1, the version WoW embeds.
set -e
cd "$(dirname "$0")/.."
run() {
	env "$@" lua5.1 tests/spell_drawer_test.lua > /dev/null
	echo "ok: ${*:-default}"
}
luac5.1 -p SpellDrawer.lua Window.lua
run
run OLD_OPEN=1
run REFUSE=ButtonFrameTemplate,PortraitFrameTemplate,BasicFrameTemplateWithInset
run REFUSE=UICheckButtonTemplate
run BARE=1
run SUB=-8 NOSLOT=1
