# Select base image
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Setup directory
RUN git clone --depth=1 --branch v2.8.5 https://github.com/discourse/discourse.git /app
WORKDIR /app

# Setup specific version of ddtrace, if specified.
ARG ddtrace_git
ENV DD_DEMO_ENV_GEM_GIT_DDTRACE ${ddtrace_git}

ARG ddtrace_ref
ENV DD_DEMO_ENV_GEM_REF_DDTRACE ${ddtrace_ref}

# Add files
COPY . /app

# Install dependencies
RUN bundle install

# Set entrypoint
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["bundle exec rails s -b 0.0.0.0"]
