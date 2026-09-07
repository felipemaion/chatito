# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM golang:1.27-bookworm AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY server/ .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/relay ./cmd/relay
RUN mkdir -p /out/data && chown 65532:65532 /out/data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/relay /relay
COPY --from=build --chown=65532:65532 /out/data /app/data
VOLUME /app/data
ENV RELAY_ADDR=:8080 RELAY_DATA_DIR=/app/data
EXPOSE 8080
ENTRYPOINT ["/relay"]
