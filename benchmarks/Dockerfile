FROM ruby:3.3.0-bullseye

# Make apt non-interactive
RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90circleci \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90circleci

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN set -ex; \
        apt-get update; \
        mkdir -p /usr/share/man/man1; \
        apt-get install -y --no-install-recommends \
            git mercurial xvfb \
            locales sudo openssh-client ca-certificates tar gzip parallel \
            net-tools netcat unzip zip bzip2 gnupg curl wget \
            tzdata rsync vim less jq; \
        rm -rf /var/lib/apt/lists/*;

# Set timezone to UTC by default
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Set language
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

# Install RubyGems
RUN mkdir -p "$GEM_HOME" && chmod -R 777 "$GEM_HOME"

# Upgrade RubyGems and Bundler
RUN gem update --system 3.3.26
RUN gem install bundler -v '~> 2.3.26'
ENV BUNDLE_SILENCE_ROOT_WARNING 1

# Reinstall a recent version of the trace to help Docker cache dependencies.
# Bump this version periodically.
RUN gem install ddtrace -v 1.20.0

WORKDIR /app

# Add base common files used by all scenarios
COPY . /app/

RUN bundle install

# Conrfigure the benchmark to run
ENV BENCHMARK=tracing_trace.rb

ENTRYPOINT ["/bin/bash", "-c"]
CMD bundle exec ruby "benchmarks/${BENCHMARK}"

