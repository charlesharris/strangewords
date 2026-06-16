.PHONY: run test vet build redis redis-stop tidy

# Start local Redis (docker), then run the server against it.
run: redis
	go run ./cmd/server

build:
	go build ./...

test:
	go test ./...

vet:
	go vet ./...

tidy:
	go mod tidy

redis:
	docker compose up -d redis

redis-stop:
	docker compose down
