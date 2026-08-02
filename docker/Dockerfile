# syntax=docker/dockerfile:1
#
# This file is based on these images:
# - https://hub.docker.com/r/hexpm/elixir/tags

# Versions
ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=28.5.0.2
ARG ALPINE_VERSION=3.23.4

# Images
ARG BUILD_IMAGE=hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}

FROM ${BUILD_IMAGE}

# Install build dependencies and tools
RUN apk add --no-cache git bash curl build-base

# Prepare build directory
WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force
