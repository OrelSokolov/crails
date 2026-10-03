# rails_hello reference (Rails 8.1.1) — oracle targets, called from
# ../../rails_hello/Makefile.
PORT ?= 3100

.PHONY: oracle-seed oracle-serve

oracle-seed:
	bin/rails db:migrate
	bin/rails runner oracle_seed.rb

oracle-serve:
	bin/rails server -p $(PORT)
