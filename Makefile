.PHONY: fmt sh.fmt lint sh.lint build test e2e up down open clean help

fmt: sh.fmt
	mise exec -- golangci-lint fmt

sh.fmt:
	mise exec -- shfmt -i 2 -w scripts/

lint: sh.lint
	mise exec -- golangci-lint run

sh.lint:
	mise exec -- shellcheck scripts/*.sh

build:
	go build -o mycli ./cmd/mycli

test:
	go test ./...

e2e: build
	bash scripts/e2e.sh

up:
	docker compose up -d

down:
	docker compose down

open:
	open http://localhost:16686

clean:
	rm -f mycli

help:
	@grep -E '^[a-zA-Z._-]+:' Makefile | sed 's/:.*//' | sort | column -t
