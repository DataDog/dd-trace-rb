FROM ruby:3.3.0-bullseye

RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90ci \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90ci

ENV DEBIAN_FRONTEND=noninteractive

RUN set -ex && \
        apt-get update && \
        mkdir -p /usr/share/man/man1 && \
        apt-get install -y --no-install-recommends \
            git mercurial xvfb \
            locales sudo openssh-client ca-certificates tar gzip parallel \
            net-tools netcat unzip zip bzip2 gnupg curl wget \
            tzdata rsync vim less jq && \
        rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

RUN mkdir -p "$GEM_HOME" && chmod -R 777 "$GEM_HOME"

RUN gem update --system 3.5.6
RUN gem install bundler -v '~> 2.5.6'
ENV BUNDLE_SILENCE_ROOT_WARNING 1

# Reinstall a recent version of the trace to help Docker cache dependencies.
# Bump this version periodically.
RUN gem install datadog -v 2.28.0

WORKDIR /app

COPY . /app/

RUN bundle install

ENV BENCHMARK=tracing_trace.rb

ENTRYPOINT ["/bin/bash", "-c"]
CMD bundle exec ruby "benchmarks/${BENCHMARK}"

