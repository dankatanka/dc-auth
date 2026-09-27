# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim

ENV BINDING="0.0.0.0"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git curl pkg-config libyaml-dev libpq-dev libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
