# This image provides the files needed to install the dd-trace-rb
# and auto instrument Ruby applications in containerized environments.
FROM alpine:3.18.3

# Set high UID to prevent possible conflict with existing users: http://www.linfo.org/uid.html
ARG UID=10000

ARG DDTRACE_RUBY_VERSION
ENV DDTRACE_RUBY_VERSION=$DDTRACE_RUBY_VERSION

ARG DDTRACE_RUBY_SHA
ENV DDTRACE_RUBY_SHA=$DDTRACE_RUBY_SHA

RUN addgroup -g 10000 -S datadog && \
    adduser -u ${UID} -S datadog -G datadog

USER ${UID}
WORKDIR /datadog-init
ADD auto_inject.rb /datadog-init/auto_inject.rb

RUN sed -i "s~<DD_TRACE_SHA_TO_BE_REPLACED>~${DDTRACE_RUBY_SHA}~g"  /datadog-init/auto_inject.rb
RUN sed -i "s~<DD_TRACE_VERSION_TO_BE_REPLACED>~${DDTRACE_RUBY_VERSION}~g"  /datadog-init/auto_inject.rb

ADD copy-lib.sh /datadog-init/copy-lib.sh
