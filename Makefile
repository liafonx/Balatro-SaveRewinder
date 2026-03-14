# Makefile — Save Rewinder test/lint targets
# Run from project root.

LUA     ?= lua
LUACHECK ?= luacheck

.PHONY: test lint check validate

test:
	$(LUA) tests/run_tests.lua

lint:
	$(LUACHECK) --config .luacheck . ; code=$$?; [ $$code -le 1 ]

validate:
	$(LUA) scripts/validate_module_map.lua

check: lint validate test
