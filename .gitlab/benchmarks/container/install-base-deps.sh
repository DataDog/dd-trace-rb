#!/usr/bin/env bash

set -ex

if [ -z "$PYENV_ROOT" ]; then
   echo "ERROR: Make sure PYENV_ROOT is set!"
   exit 1
fi

apt-get update && apt-get -y install --no-install-recommends \
        hwinfo \
        procps \
        git \
        curl \
        software-properties-common \
        build-essential \
        libnss3-dev zlib1g-dev libgdbm-dev libncurses5-dev libssl-dev libffi-dev libreadline-dev libsqlite3-dev libbz2-dev \
        apt-transport-https \
        ca-certificates \
        openssl \
        tzdata \
        openssh-client \
        parallel \
        zip \
        unzip \
        jq \
        uuid-runtime \
        make wget llvm \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev liblzma-dev \
   && apt-get -y clean \
   && rm -rf /var/lib/apt/lists/*

git clone --depth 1 https://github.com/pyenv/pyenv.git --branch "v2.4.1" --single-branch "$PYENV_ROOT"
pyenv install 3.9.15 && pyenv global 3.9.15

pip3 install awscli virtualenv setuptools
