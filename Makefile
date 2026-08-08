# g-monster — Connect IQ build, test and run.
#
# The SDK path is read from the Connect IQ SDK Manager's own config rather than pinned to a
# version, so upgrading the SDK does not require editing this file. Override anything on the
# command line:  make test DEVICE=fr55

CIQ_HOME  := $(HOME)/Library/Application Support/Garmin/ConnectIQ
SDK       ?= $(shell tr -d '\n' < "$(CIQ_HOME)/current-sdk.cfg" 2>/dev/null | sed 's:/*$$::')
DEVICE    ?= fenix6pro
KEY       ?= developer_key.der

# -l 3 is the strictest type checking the compiler offers. Everything here builds clean at it,
# so anything less would be a step backwards.
TYPECHECK ?= -l 3

MONKEYC   := $(SDK)/bin/monkeyc
MONKEYDO  := $(SDK)/bin/monkeydo
SIMULATOR := $(SDK)/bin/connectiq

PRG       := GMonster.prg
TEST_PRG  := GMonsterTest.prg
IQ        := GMonster.iq
JUNGLE    := monkey.jungle

# Products the manifest claims, narrowed to those with a simulator device installed — the
# compiler cannot target a device whose files are absent.
PRODUCTS   := $(shell sed -n 's/.*<iq:product id="\([^"]*\)".*/\1/p' manifest.xml)
# $(wildcard) cannot be used here: it splits on spaces, and the SDK path contains one.
INSTALLED  := $(shell ls -1 "$(CIQ_HOME)/Devices" 2>/dev/null)
CHECKABLE  := $(filter $(INSTALLED),$(PRODUCTS))

# Debug switches, passed through the environment. Monkey C has no preprocessor and a watch app has
# no runtime environment, so these are compiled in: gen_debug_config.py turns them into
# source/DebugConfig.mc before every build. Unset means off.
#
#   make run DEBUG_FORCE_ACTION=move
#   DEBUG_INSTANT_BATTLE=1 DEBUG_BATTLE_ENEMY=twinflare make run
#
# `?=` so a value already exported in the shell wins, and `export` so a value given on the make
# command line reaches the generator.
DEBUG_INSTANT_BATTLE ?=
DEBUG_BATTLE_ENEMY   ?=
DEBUG_BATTLE_IS_BOSS ?=
DEBUG_EVENT_GAP      ?=
DEBUG_FORCE_ACTION   ?=
export DEBUG_INSTANT_BATTLE DEBUG_BATTLE_ENEMY DEBUG_BATTLE_IS_BOSS DEBUG_EVENT_GAP DEBUG_FORCE_ACTION

DEBUGGEN := python3 tools/debug/gen_debug_config.py

.DEFAULT_GOAL := help
.PHONY: help build release test run sim package install check clean devices doctor debug-config debug-off debug-status

help:
	@echo "g-monster — Connect IQ"
	@echo
	@echo "  make build      compile for $(DEVICE) (debug, strict type check)"
	@echo "  make release    compile optimised"
	@echo "  make test       compile with tests and run them in the simulator"
	@echo "  make run        compile and side-load into the simulator"
	@echo "  make sim        start the simulator if it is not already up"
	@echo "  make check      compile for every supported device with a simulator installed"
	@echo "  make package    build the .iq store bundle for all products"
	@echo "  make install    copy onto a Garmin watch mounted as a USB volume"
	@echo "  make clean      remove build output"
	@echo "  make doctor     show the resolved toolchain"
	@echo
	@echo "  DEVICE=$(DEVICE)   (override: make test DEVICE=fr55)"
	@echo
	@echo "Debug switches (compiled in; unset means off):"
	@echo "  DEBUG_INSTANT_BATTLE=1        boot straight into a battle"
	@echo "  DEBUG_BATTLE_ENEMY=<species>  which creature to fight there"
	@echo "  DEBUG_BATTLE_IS_BOSS=1        show it as an area guardian"
	@echo "  DEBUG_EVENT_GAP=<steps>       steps between trek events (0 = real pacing)"
	@echo "  DEBUG_FORCE_ACTION=<pose>     idle|sleep|move|fight"
	@echo
	@echo "  e.g.  make run DEBUG_FORCE_ACTION=move"
	@echo "        make debug-status     show what the built binary has on"
	@echo "        make debug-off        clear every switch"

# Fail loudly and early rather than emitting a confusing 'no such file' from the compiler.
doctor:
	@test -n "$(SDK)" || { echo "No SDK found. Is the Connect IQ SDK Manager installed?"; exit 1; }
	@test -x "$(MONKEYC)" || { echo "monkeyc missing at: $(MONKEYC)"; exit 1; }
	@test -f "$(KEY)" || { echo "Signing key missing: $(KEY)"; exit 1; }
	@echo "SDK:       $(SDK)"
	@echo "device:    $(DEVICE)"
	@echo "key:       $(KEY)"
	@echo "checkable: $(CHECKABLE)"

build: doctor debug-config
	@echo "==> build $(DEVICE)"
	@"$(MONKEYC)" -d $(DEVICE) -f $(JUNGLE) -o $(PRG) -y $(KEY) $(TYPECHECK)

# --off ignores the environment, so a switch left exported in a shell cannot ride into a release.
release: doctor debug-off
	@echo "==> release $(DEVICE)"
	@"$(MONKEYC)" -d $(DEVICE) -f $(JUNGLE) -o $(PRG) -y $(KEY) $(TYPECHECK) -r

# Tests are (:test)-annotated, so monkeyc only compiles them into a --unit-test build.
$(TEST_PRG): doctor debug-config
	@echo "==> build tests $(DEVICE)"
	@"$(MONKEYC)" -d $(DEVICE) -f $(JUNGLE) -o $(TEST_PRG) -y $(KEY) $(TYPECHECK) --unit-test

# The simulator is a separate process that must already be up; monkeydo only talks to it.
sim:
	@if pgrep -f "ConnectIQ.app" >/dev/null 2>&1; then \
	  echo "==> simulator already running"; \
	else \
	  echo "==> starting simulator"; \
	  "$(SIMULATOR)" >/tmp/ciq-sim.log 2>&1 & \
	  for i in $$(seq 1 30); do \
	    pgrep -f "ConnectIQ.app" >/dev/null 2>&1 && break; \
	    sleep 1; \
	  done; \
	  sleep 4; \
	fi

test: $(TEST_PRG)
	@$(MAKE) --no-print-directory sim
	@echo "==> run tests"
	@"$(MONKEYDO)" $(TEST_PRG) $(DEVICE) -t

# monkeydo stays in the foreground for as long as the app runs. That is not a hang — Ctrl-C to stop.
run: build
	@$(MAKE) --no-print-directory sim
	@echo "==> side-load (Ctrl-C to stop)"
	@"$(MONKEYDO)" $(PRG) $(DEVICE)

# -e builds every product in the manifest, which is what the store expects.
# Same guard as release: a store bundle is generated with every switch off, never from the shell.
package: doctor debug-off
	@echo "==> package $(IQ)"
	@"$(MONKEYC)" -e -f $(JUNGLE) -o $(IQ) -y $(KEY) $(TYPECHECK)

# Guards against the trap of a device list that has drifted from what is actually buildable.
check: doctor debug-config
	@for d in $(CHECKABLE); do \
	  printf '%-16s ' "$$d"; \
	  "$(MONKEYC)" -d $$d -f $(JUNGLE) -o /tmp/check-$$d.prg -y $(KEY) $(TYPECHECK) >/tmp/check-$$d.log 2>&1 \
	    && echo OK || { echo FAIL; sed -n '1,6p' /tmp/check-$$d.log; }; \
	done

# Only works for watches that present as USB mass storage. Many models from ~2021 on speak MTP
# instead, never mount as a volume, and have to go through Garmin Express.
install: release
	@vol=$$(ls -d /Volumes/*/GARMIN 2>/dev/null | head -1); \
	if [ -z "$$vol" ]; then \
	  echo "No Garmin volume mounted."; \
	  echo "Check Settings > System > USB Mode > Garmin (not MTP), then replug."; \
	  exit 1; \
	fi; \
	mkdir -p "$$vol/APPS"; \
	cp -f $(PRG) "$$vol/APPS/" && echo "installed to $$vol/APPS/$(PRG) — eject before unplugging"

# Regenerates source/DebugConfig.mc from the DEBUG_* environment and prints what is on, so the
# build log always records the debug state rather than leaving it to be discovered on the watch.
debug-config:
	@$(DEBUGGEN)

debug-off:
	@$(DEBUGGEN) --off

debug-status:
	@$(DEBUGGEN) --check --quiet >/dev/null 2>&1 || echo "(source/DebugConfig.mc does not match the current environment)"
	@sed -n 's/^    const \([A-Z_]*\) = \(.*\);$$/  \1 = \2/p' source/DebugConfig.mc

clean:
	@rm -f $(PRG) $(TEST_PRG) $(IQ) *.prg.debug.xml /tmp/check-*.prg /tmp/check-*.log
	@rm -rf bin gen
	@echo "==> cleaned"

devices:
	@echo "$(INSTALLED)" | tr ' ' '\n'

