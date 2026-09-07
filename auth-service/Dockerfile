FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app .

FROM alpine:3.19

RUN apk add --no-cache ca-certificates wget && \
    addgroup -S appgroup && \
    adduser -S appuser -G appgroup

COPY --from=builder /app /app

USER appuser

EXPOSE 8001

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8001/health || exit 1

CMD ["/app"]
