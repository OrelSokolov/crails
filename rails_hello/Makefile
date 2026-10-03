# rails_hello — integration app on the full CRails stack (Iteration 6).
#
# The Ruby reference lives in ../bench/rails_hello (Rails 8.1.1); this app
# is its 1:1 mirror. One HTTP harness (oracle/http_cases.rb) runs against
# both; both must pass with the same oracle/expected.yml (AGENTS.md rule).

RAILS_REF ?= ../bench/rails_hello
RAILS_PORT ?= 3100
CRAILS_PORT ?= 3101

.PHONY: help oracle-record oracle-check seed-crails

help:
	@echo "make oracle-record  # boot Rails ref, seed, record expected.yml"
	@echo "make oracle-check   # boot CRails app, seed, check against expected.yml"
	@echo "make seed-crails    # TRUNCATE + seed the CRails PG database"

oracle-record:
	$(MAKE) -C $(RAILS_REF) oracle-seed
	$(MAKE) -C $(RAILS_REF) oracle-serve PORT=$(RAILS_PORT) & \
	  sleep 6; \
	  ruby oracle/http_cases.rb record http://localhost:$(RAILS_PORT); \
	  rc=$$?; kill %1 2>/dev/null; exit $$rc

oracle-check: seed-crails
	./bin/crails server & \
	  sleep 2; \
	  ruby oracle/http_cases.rb check http://localhost:$(CRAILS_PORT); \
	  rc=$$?; kill %1 2>/dev/null; exit $$rc

seed-crails:
	psql -U root -h /var/run/postgresql -d crails_hello_test -c \
	  "TRUNCATE posts RESTART IDENTITY; INSERT INTO posts (title, body, views, created_at, updated_at) VALUES ('first post', 'hello world', 3, '2026-10-02 12:00:00', '2026-10-02 12:00:00'), ('second post', NULL, 0, '2026-10-02 12:00:00', '2026-10-02 12:00:00'), ('third & <post>', NULL, 42, '2026-10-02 12:00:00', '2026-10-02 12:00:00');"
