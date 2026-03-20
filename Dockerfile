# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolve issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=1.19.5-erlang-28
# https://hub.docker.com/_/debian?tab=tags&name=trixie-20250317-slim
#
# This file is based on the output of `mix phx.gen.release --docker`.

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=trixie-20250317-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ---- Build stage ----
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config before compiling deps
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile the release
COPY config/runtime.exs config/
RUN mix compile

# Build the release
COPY rel rel
RUN mix release

# ---- Runner stage ----
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/trivia_platform ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes,
# set the BEAM to be PID 1
CMD ["/app/bin/server"]
