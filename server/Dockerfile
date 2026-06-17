# Build a static server binary, then ship it in a minimal image.
FROM golang:1.26-alpine AS build
WORKDIR /src

# Cache module downloads first.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 app
USER app
COPY --from=build /server /server
ENV SW_ADDR=":8080"
EXPOSE 8080
ENTRYPOINT ["/server"]
