# This image provides the files needed to install the dd-trace-rb
# and auto instrument Ruby applications in containerized environments.
FROM alpine:3.18.6

# Set high UID to prevent possible conflict with existing users: http://www.linfo.org/uid.html
ARG UID=10000

ARG DATADOG_RUBY_GEM_VERSION
ENV DATADOG_RUBY_GEM_VERSION=$DATADOG_RUBY_GEM_VERSION

ARG DATADOG_RUBY_GEM_SHA
ENV DATADOG_RUBY_GEM_SHA=$DATADOG_RUBY_GEM_SHA

RUN addgroup -g 10000 -S datadog && \
    adduser -u ${UID} -S datadog -G datadog

USER ${UID}
WORKDIR /datadog-init
ADD auto_inject.rb /datadog-init/auto_inject.rb

RUN sed -i "s~<DATADOG_GEM_SHA_TO_BE_REPLACED>~${DATADOG_RUBY_GEM_SHA}~g"  /datadog-init/auto_inject.rb
RUN sed -i "s~<DATADOG_GEM_VERSION_TO_BE_REPLACED>~${DATADOG_RUBY_GEM_VERSION}~g"  /datadog-init/auto_inject.rb

ADD copy-lib.sh /datadog-init/copy-lib.sh
