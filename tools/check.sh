#!/usr/bin/env sh
# Syntax-check every Lua file and run the smoke test against stubbed Isaac API.
set -e
cd "$(dirname "$0")/.."
LUAC=${LUAC:-luac5.3}
LUA=${LUA:-lua5.3}
find . -name '*.lua' -not -path './.git/*' | while read -r f; do "$LUAC" -p "$f"; done
echo "syntax ok"
"$LUA" tools/smoke.lua
