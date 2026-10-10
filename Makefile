# Usage:  make install ROKU_IP=192.168.1.50 ROKU_PASS=yourdevpassword
ROKU_IP   ?= $(shell cat .roku_ip 2>/dev/null)
ROKU_PASS ?= $(shell cat .roku_pass 2>/dev/null)
ZIP := out/iptv-live.zip

.PHONY: zip install test unit lint clean

zip:
	@mkdir -p out && rm -f $(ZIP)
	@zip -qr $(ZIP) manifest source components images -x '*.DS_Store'
	@echo "Built $(ZIP)"

install: zip
	@test -n "$(ROKU_IP)" || (echo "Set ROKU_IP=<your roku ip>"; exit 1)
	@curl -sS --digest --user "rokudev:$(ROKU_PASS)" -F "mysubmit=Install" -F "archive=@$(ZIP)" \
		"http://$(ROKU_IP)/plugin_install" | grep -oE "Install Success|Identical to previous version|Install Failure[^<]*|Unauthorized" | head -1

# Runs utils tests on the device; read results with: telnet $(ROKU_IP) 8085
test: install
	@curl -sS -d '' "http://$(ROKU_IP):8060/launch/dev?runTests=true" && echo "Launched tests; see telnet $(ROKU_IP) 8085"

# Runs utils tests locally under brs-engine
unit:
	@npx -y -p brs-node brs-cli source/utils.brs source/tests.brs tools/test_main.brs

# Static check (syntax, undefined functions, component wiring)
lint:
	@npx -y brighterscript --rootDir . --createPackage false --files manifest "source/**/*" "components/**/*" "images/**/*"

clean:
	rm -rf out
