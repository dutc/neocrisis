curpath := $(abspath $(lastword $(MAKEFILE_LIST)))
curdir  := $(dir $(curpath))

ifeq (,$(wildcard $(curdir)/env))
	SHELL = /bin/zsh
else
	SHELL = $(curdir)/env /bin/zsh
endif

.PHONY: test test-model test-bitemporal test-data test-queries
test: | test-cli test-model test-bitemporal test-data test-queries
test-cli:
	@which psql jinja2 python bash zsh >/dev/null || exit 1
test-model:
	psql -d nc <<( $(curdir)/model.sh )
test-bitemporal:
	psql -d nc <<( $(curdir)/bitemporal/bitemporal.sh )
test-data:
	psql -d nc < $(curdir)/data.sql
test-queries:
	psql -d nc < $(curdir)/queries.sql

.PHONY: shell
shell:
	PSQLRC=$(curdir)/utils/psqlrc psql -d nc

.PHONY: run-db
run-db:
	$(curdir)/utils/run-db.sh $(DB)

.PHONY: setup-db
setup-db:
	-rm "$(curdir)/db" "$(curdir)/db-logs" -rf
	-mkdir -p "$(curdir)/db" "$(curdir)/db-logs"
	initdb "$(curdir)/db"
	pg_ctl -D "$(curdir)/db" -l "$(curdir)/db-logs/setup.log" start
	createdb nc
	pg_ctl -D "$(curdir)/db" stop
