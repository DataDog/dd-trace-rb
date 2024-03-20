# Note: See the "Publishing updates to images" note in ./README.md for how to publish new builds of this container image
#
# Here be dragons: Last time we tried to move away from Debian stretch, we ran into issues with two gems that are used in some
# of our CI tests/test apps.
# If you're going to try your luck, make sure that the following work after your changes:
# gem install nokogiri -v '= 1.10.10'
# gem install mysql
#
# Last version: https://github.com/docker-library/ruby/blob/31f66490fdb837ddcc5896e3275f2188f2b7b6dd/2.3/stretch/Dockerfile
FROM ruby:2.3.8-stretch

# Make apt non-interactive
RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90circleci \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90circleci

ENV DEBIAN_FRONTEND=noninteractive

# Pull packages from debian archive, old repos don't work any more
RUN echo "deb [trusted=yes] http://archive.debian.org/debian/ stretch main contrib non-free" | tee /etc/apt/sources.list

# Install required packages
RUN set -ex; \
        apt-get update; \
        mkdir -p /usr/share/man/man1; \
        apt-get install --force-yes --no-install-recommends \
            git mercurial xvfb \
            locales sudo openssh-client ca-certificates tar gzip parallel \
            net-tools netcat unzip zip bzip2 gnupg curl wget \
            tzdata rsync vim less jq iptables; \
        rm -rf /var/lib/apt/lists/*;

# Set timezone to UTC by default
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Set language
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

# Install Docker
RUN set -ex \
  && export DOCKER_VERSION=$(curl --silent --fail --retry 3 https://download.docker.com/linux/static/stable/$(arch)/ | grep -o -e 'docker-[.0-9]*-ce\.tgz' | sort -r | head -n 1) \
  && DOCKER_URL="https://download.docker.com/linux/static/stable/$(arch)/${DOCKER_VERSION}" \
  && echo DOCKER_URL: $DOCKER_URL \
  && curl --silent --show-error --location --fail --retry 3 --output /tmp/docker.tgz "${DOCKER_URL}" \
  && ls -lha /tmp/docker.tgz \
  && tar -xz -C /tmp -f /tmp/docker.tgz \
  && mv /tmp/docker/* /usr/bin \
  && rm -rf /tmp/docker /tmp/docker.tgz \
  && which docker \
  && (docker version || true)

# Install Docker Compose (1.8.0, fairly old)
RUN echo 'deb [trusted=yes] http://archive.debian.org/debian/ stretch-backports main' > /etc/apt/sources.list.d/stretch-backports.list \
  && apt-get update \
  && apt-get install -y docker-compose \
  && docker-compose version \
  && rm -rf /var/lib/apt/lists/*

# Install Dockerize
RUN DOCKERIZE_URL="https://github.com/powerman/dockerize/releases/download/v0.17.0/dockerize-$(uname -s | tr '[:upper:]' '[:lower:]')-$(arch | sed 's/aarch64/arm64/')" \
  && echo DOCKERIZE_URL: $DOCKERIZE_URL \
  && curl --silent --show-error --location --fail --retry 3 --output /usr/local/bin/dockerize $DOCKERIZE_URL \
  && chmod +x /usr/local/bin/dockerize \
  && dockerize --version

# Install RubyGems
RUN mkdir -p "$GEM_HOME" && chmod -R 777 "$GEM_HOME"

# Install RubyGems and Bundler
# NOTE: Rubygems 3.0.6 is the last version that seems to work fine in this image AND not drag bundler 2 along.
# Later versions are either broken or they force the use of bundler 2, which we can't use because some of our
# dependencies (e.g. rails 3.0.20) don't like it.
RUN gem update --system '3.0.6'
# Ruby 2.3 can support Bundler 2+
# But hold back to < 2 for now, because some dependencies require it.
RUN gem install bundler -v '1.17.3'
ENV BUNDLE_SILENCE_ROOT_WARNING 1

RUN mkdir /app
WORKDIR /app

CMD ["/bin/sh"]
