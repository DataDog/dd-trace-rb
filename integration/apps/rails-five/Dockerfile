# Select base image
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Setup directory
RUN mkdir /app
WORKDIR /app

# Setup specific version of datadog, if specified.
ARG gem_git_datadog
ENV DD_DEMO_ENV_GEM_GIT_DATADOG ${gem_git_datadog}

ARG gem_ref_datadog
ENV DD_DEMO_ENV_GEM_REF_DATADOG ${gem_ref_datadog}

# Install dependencies
COPY Gemfile /app/Gemfile
RUN bundle install

# Add files
COPY . /app

# Set entrypoint
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["bin/setup && bin/run"]
