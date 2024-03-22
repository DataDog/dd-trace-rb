# ruby:2.2.10-jessie was based on jessie, and had a aarch64 image
# aarch64 used to be supported upon release but is not part of LTS,
# so archive.debian.org does not contain aarch64: https://www.debian.org/releases/jessie/

# Note: See the "Publishing updates to images" note in ./README.md for how to publish new builds of this container image

# Here be dragons: Last time we tried to move away from Debian stretch, we ran into issues with two gems that are used in some
# of our CI tests/test apps.
# If you're going to try your luck, make sure that the following work after your changes:
# gem install mysql
#
# taken from https://github.com/docker-library/ruby/blob/b5ef401d348ca9b1d9f6a5cb4b25f32bf013daca/2.2/jessie/Dockerfile
FROM buildpack-deps:stretch AS ruby-2.2.10-stretch

# skip installing gem documentation
RUN mkdir -p /usr/local/etc \
  && { \
    echo 'install: --no-document'; \
    echo 'update: --no-document'; \
  } >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.2
ENV RUBY_VERSION 2.2.10
ENV RUBY_DOWNLOAD_SHA256 bf77bcb7e6666ccae8d0882ea12b05f382f963f0a9a5285a328760c06a9ab650
ENV RUBYGEMS_VERSION 2.7.11
ENV BUNDLER_VERSION 1.17.3

# Pull packages from debian archive, old repos don't work any more
RUN echo "deb [trusted=yes] http://archive.debian.org/debian/ stretch main contrib non-free" | tee /etc/apt/sources.list

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
RUN set -ex \
  && apt-get update \
  # ruby 2.2 needs libssl1.0-dev
  && apt-get install -y --no-install-recommends wget \
  && apt-get remove -y libssl-dev libcurl4-openssl-dev \
  && ARCH=$(dpkg --print-architecture) \
  && wget "https://snapshot.debian.org/archive/debian-security/20220317T093342Z/pool/updates/main/o/openssl1.0/libssl1.0.2_1.0.2u-1~deb9u7_${ARCH}.deb" \
  && dpkg -i libssl1.0.2*.deb \
  && rm -rf libssl1.0.2*.deb \
  && wget "https://snapshot.debian.org/archive/debian-security/20220317T093342Z/pool/updates/main/o/openssl1.0/libssl1.0-dev_1.0.2u-1~deb9u7_${ARCH}.deb" \
  && dpkg -i libssl1.0-dev*.deb \
  && rm -rf libssl1.0-dev*.deb \
# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
  && buildDeps=' \
    bison \
    dpkg-dev \
    libgdbm-dev \
    ruby \
  ' \
  && apt-get install -y --no-install-recommends $buildDeps \
  && rm -rf /var/lib/apt/lists/* \
  \
  && wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz" \
  && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum -c - \
  \
  && mkdir -p /usr/src/ruby \
  && tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1 \
  && rm ruby.tar.xz \
  \
  && cd /usr/src/ruby \
  \
# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
  && { \
    echo '#define ENABLE_PATH_CHECK 0'; \
    echo; \
    cat file.c; \
  } > file.c.new \
  && mv file.c.new file.c \
  \
  && autoconf \
  && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
  && ./configure \
    --build="$gnuArch" \
    --disable-install-doc \
    --enable-shared \
  && make -j "$(nproc)" \
  && make install \
  \
  && apt-get purge -y --auto-remove $buildDeps \
  && cd / \
  && rm -r /usr/src/ruby \
  \
  && gem update --system "$RUBYGEMS_VERSION" \
  && gem install bundler --version "$BUNDLER_VERSION" --force \
  && rm -r /root/.gem/

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_BIN="$GEM_HOME/bin" \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
  && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

CMD [ "irb" ]

FROM ruby-2.2.10-stretch

# Make apt non-interactive
RUN echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90circleci \
  && echo 'DPkg::Options "--force-confnew";' >> /etc/apt/apt.conf.d/90circleci

ENV DEBIAN_FRONTEND=noninteractive

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

RUN mkdir /app
WORKDIR /app

CMD ["/bin/sh"]
