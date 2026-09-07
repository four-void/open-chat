.PHONY: setup build run lint fmt test db.setup db.create db.migrate db.seed db.drop db.reset repl repl.run repl.test

# Project-wide

setup:
	$(MAKE) build \
	&& $(MAKE) db.setup

build:
	mix do deps.get + compile

run:
	mix phx.server

# Code quality

lint:
	mix format --check-formatted

fmt:
	mix format

test:
	mix test

# Database

db.setup:
	$(MAKE) db.create \
	&& $(MAKE) db.migrate \
	&& $(MAKE) db.seed

db.create:
	mix ecto.create

db.migrate:
	mix ecto.migrate

db.seed:
	mix run priv/repo/seeds.exs

db.drop:
	mix ecto.drop

db.reset:
	$(MAKE) db.drop \
	&& $(MAKE) db.setup

# REPL

repl:
	iex -S mix

repl.run:
	iex -S mix phx.server

repl.test:
	iex -S mix test
