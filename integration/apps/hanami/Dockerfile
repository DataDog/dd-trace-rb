# Select base image
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Setup directory
RUN mkdir /app
WORKDIR /app

# Setup specific version of ddtrace, if specified.
ARG ddtrace_git
ENV DD_DEMO_ENV_GEM_GIT_DDTRACE ${ddtrace_git}

ARG ddtrace_ref
ENV DD_DEMO_ENV_GEM_REF_DDTRACE ${ddtrace_ref}

# Install dependencies
COPY Gemfile /app/Gemfile
RUN bundle install

# Add files
COPY . /app

# Set entrypoint
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["bin/setup && bin/run"]
