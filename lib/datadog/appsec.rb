require 'datadog/appsec/configuration'
require 'datadog/appsec/extensions'

module Datadog
  # Namespace for Datadog AppSec instrumentation
  module AppSec
    include Configuration

    def self.writer
      @writer ||= Writer.new
    end

    # Expose AppSec to global shared objects
    Extensions.activate!
  end
end

# Integrations
require 'datadog/appsec/contrib/rack/integration'
require 'datadog/appsec/contrib/sinatra/integration'
require 'datadog/appsec/contrib/rails/integration'
