# Multi-stage: compila com o toolchain Go e roda em imagem distroless (sem shell,
# sem gerenciador de pacotes, usuário não-root) — superfície mínima para o scan do Trivy.
FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/main .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /out/main /app/main
EXPOSE 8001
USER nonroot:nonroot
ENTRYPOINT ["/app/main"]
