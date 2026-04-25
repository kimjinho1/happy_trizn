# Multi-stage Phoenix 1.8 release Dockerfile.
# Build stage: hexpm 공식 elixir + erlang debian 이미지로 컴파일.
# Runtime stage: 가벼운 debian-slim + 런타임 종속성만.
# syntax=docker/dockerfile:1.7  (BuildKit cache mount 지원)

ARG ELIXIR_VERSION=1.16.3
ARG OTP_VERSION=26.2.5
ARG DEBIAN_VERSION=bookworm-20240612-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ---------- Build stage ----------
FROM ${BUILDER_IMAGE} AS builder

# 빌드 의존성
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"
# Hex registry 응답 늦으면 timeout 늘림 (default 5s 너무 짧음)
ENV HEX_HTTP_TIMEOUT="120"
ENV HEX_HTTP_CONCURRENCY="2"

# deps 먼저 (캐시 효율). BuildKit cache mount 로 hex 메타데이터 + mix archive
# 캐시만 보존 → 두번째 빌드부터 deps.get 거의 즉시. deps/ 는 layer 로 남겨야
# 이후 단계가 사용 가능 (cache mount 안 함).
COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile

# 코드 복사
COPY priv priv
COPY lib lib
COPY assets assets

# 컴파일 먼저 — Phoenix LiveView 1.1 의 phoenix-colocated/<app> 디렉토리는
# `mix compile` 시 자동 생성됨. 이게 있어야 esbuild 가 import 해결 가능.
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix compile

# 그 다음 asset 빌드 (tailwind + esbuild minify + phx.digest)
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix assets.deploy

# runtime config 와 release overlay
COPY config/runtime.exs config/
COPY rel rel

# 안전망: git +x 비트 누락 / Windows 체크아웃 등에서도 실행 권한 보장
RUN chmod +x rel/overlays/bin/server rel/overlays/bin/migrate

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release

# ---------- Runtime stage ----------
FROM ${RUNNER_IMAGE} AS runtime

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# UTF-8 로케일
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/happy_trizn ./

USER nobody

# rel/overlays/bin/server 가 PHX_SERVER=true 세팅 후 happy_trizn start 실행
CMD ["/app/bin/server"]
