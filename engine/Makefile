#!/usr/bin/make -f

ifneq (,$(wildcard $(PWD)/env))
	SHELL := $(PWD)/env /bin/zsh
else
	SHELL := /bin/zsh
endif

makefile   := $(lastword $(MAKEFILE_LIST))
abscurpath := $(shell realpath $(abspath $(makefile)))
relcurpath := $(shell realpath --relative-to="$(PWD)" $(abspath $(makefile)))
abscurdir  := $(dir $(abscurpath))
relcurdir  := $(dir $(relcurpath))
curpath    := $(relcurpath)
curdir     := $(relcurdir)

PSQL := PSQLRC="$(curdir)/utils/psqlrc" psql $(PSQL_FLAGS) -d nc

.PHONY: help
help:
	@echo 'Targets:'
	@echo ''
	@echo '`make shell`               launches pg shell'
	@echo '`make run-db`              runs pg with `run-db` script'
	@echo '`make setup-db`            clears & sets up pg database'
	@echo ''
	@echo '`make stress-test`         runs `make test` loop STRESS_TEST_PASSES times'
	@echo '                           to identify potential state/ordering issues'
	@echo ''
	@echo '`make test`                runs...'
	@echo '   `make test-model`       populate model information'
	@echo '   `make test-data`        populate sample data'
	@echo '   `make test-bitemporal`  activate bitemporality'
	@echo '   `make test-checks`      runs checks'
	@echo '   `make test-queries`     runs spot-check queries'
	@echo ''
	@echo '`make setup`               runs...'
	@echo '   `make test-model`       populate model information'
	@echo '   `make test-bitemporal`  activate bitemporality'

.PHONY: test setup test-model test-bitemporal test-data test-queries
test: | test-cli test-model test-bitemporal test-data test-checks test-queries
setup: | test-cli test-model test-bitemporal
test-cli:
	@which psql jinja2 python bash zsh >/dev/null || exit 1
test-model: $(curdir)/model.sql
	$(PSQL) < $<
test-bitemporal: $(curdir)/bitemporal/bitemporal.sh $(curdir)/bitemporal/bitemporal.sql.template
	$(PSQL) <<( $<  )
test-data: $(curdir)/data.sql
	$(PSQL) < $<
test-checks: $(curdir)/checks.sql
	$(PSQL) < $<
test-queries: $(curdir)/queries.sql
	$(PSQL) < $<

STRESS_TEST_PASSES ?= 10
.PHONY: stress-test
stress-test:
	for pass in $$(seq 1 $(STRESS_TEST_PASSES)); do \
		clear; \
		echo "Pass: $$pass (started)"; \
		PSQL_FLAGS=-q make -s -f "$(curpath)" test || break; \
		echo "Pass: $$pass (successful)"; \
	done; \
	[[ $$pass == $(STRESS_TEST_PASSES) ]] && echo "Stress test successful!"

.PHONY: shell
shell:
	@$(PSQL) -q -c '\pset footer off' -c '\dt game.*'
	@$(PSQL) -q -c '\pset footer off' -c '\dv game.*'
	@$(PSQL) -q -c '\pset footer off' -c '\dm game.*'
	@$(PSQL) -q

.PHONY: run-db
run-db:
	$(curdir)/utils/run-db $(DB)

.PHONY: setup-db
setup-db:
	-@rm "$(curdir)/db" "$(curdir)/db-logs" -rf
	-@mkdir -p "$(curdir)/db" "$(curdir)/db-logs"
	initdb "$(curdir)/db"
	pg_ctl -D "$(curdir)/db" -l "$(curdir)/db-logs/setup.log" start
	createdb nc
	pg_ctl -D "$(curdir)/db" stop

.PHONY: debug
debug:
	@echo abscurpath=$(abscurpath)
	@echo relcurpath=$(relcurpath)
	@echo curpath=$(curpath)
	@echo abscurdir=$(abscurdir)
	@echo relcurdir=$(relcurdir)
	@echo curdir=$(curdir)
