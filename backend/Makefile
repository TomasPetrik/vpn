.PHONY: tidy build migrate serve test

export DATABASE_DSN ?= vpn_app:vpn_dev_app@tcp(127.0.0.1:33070)/vpn?parseTime=true&loc=UTC&time_zone=%27%2B00%3A00%27
export DEVICE_ID_HMAC_KEY ?= local-dev-hmac-key-change-me
export HTTP_ADDR ?= 127.0.0.1:8090
export WG_DRIVER ?= fake

tidy:
	go mod tidy

build:
	go build -o bin/vpn-api ./cmd/vpn-api

migrate: build
	./bin/vpn-api migrate up

serve: build
	./bin/vpn-api serve

test:
	go test ./...
