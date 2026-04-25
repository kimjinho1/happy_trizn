# Multi-stage Phoenix 1.8 release Dockerfile.
# Build stage: hexpm 공식 elixir + erlang debian 이미지로 컴파일.
# Runtime stage: 가벼운 debian-slim + 런타임 종속성만.

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

# deps 먼저 (캐시 효율)
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# asset 빌드
COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy

# 컴파일 (config 만 있으면 컴파일러가 끌어다 씀)
RUN mix compile

# runtime config 와 release overlay
COPY config/runtime.exs config/
COPY rel rel

RUN mix release

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
