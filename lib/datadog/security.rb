require 'datadog/security/configuration'

module Datadog
  # Namespace for Datadog Security instrumentation
  module Security
    include Configuration
  end
end

# Integrations
require 'datadog/security/contrib/rack/integration'
require 'datadog/security/contrib/sinatra/integration'
require 'datadog/security/contrib/rails/integration'
