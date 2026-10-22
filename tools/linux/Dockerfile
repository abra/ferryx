# Linux to build and test Ferryx on from a Mac or any other desk: Flutter at
# the version `.fvmrc` pins, stable Rust and the GTK packages a desktop
# build needs. `make linux` builds and runs it (see tools/linux/run.sh).
FROM ubuntu:24.04

ARG FLUTTER_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates clang cmake curl git libgtk-3-dev \
      liblzma-dev libstdc++-12-dev make ninja-build pkg-config rsync unzip \
      xvfb xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

# Flutter from its repository: the release archives are x64 only, and an
# arm64 Mac runs arm64 containers.
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:/root/.cargo/bin:$PATH
RUN flutter config --no-analytics --enable-linux-desktop \
    && dart --disable-analytics \
    && flutter precache --linux

RUN curl -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --component rustfmt,clippy

WORKDIR /work
