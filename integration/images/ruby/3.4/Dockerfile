FROM ruby:3.4

ENV DEBIAN_FRONTEND=noninteractive

# Install prerequisites
RUN set -ex && \
        echo "===> Installing dependencies" && \
        apt-get -y update && \
        apt-get install -y --force-yes --no-install-recommends \
            curl wget tar gzip gnupg apt-transport-https ca-certificates tzdata locales && \
        \
        echo "===> Installing NodeJS" && \
        apt-get install -y --force-yes --no-install-recommends nodejs && \
        \
        echo "===> Installing Yarn" && \
        curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
        echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
        apt-get update && \
        apt-get install -y --force-yes --no-install-recommends yarn && \
        \
        echo "===> Installing database libraries" && \
        apt-get install -y --force-yes --no-install-recommends \
            postgresql-client sqlite3 && \
        \
        echo "===> Installing dev tools" && \
        mkdir -p /usr/share/man/man1 && \
        apt-get install -y --force-yes --no-install-recommends \
            sudo git openssh-client rsync vim \
            net-tools netcat-openbsd parallel unzip zip bzip2 && \
        \
        echo "===> Cleaning up" && \
        rm -rf /var/lib/apt/lists/*;

# Set timezone to UTC by default
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Set language
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

# Install RubyGems
RUN gem update --system 3.4.1
RUN mkdir -p "$GEM_HOME" && chmod -R 777 "$GEM_HOME"

# Upgrade RubyGems and Bundler
RUN gem update --system 3.4.1
RUN gem install bundler
ENV BUNDLE_SILENCE_ROOT_WARNING 1

# Setup demo environment includes
COPY ./include /vendor/dd-demo
ENV RUBYLIB /vendor/dd-demo
ENV RUBYOPT -rdatadog/demo_env
