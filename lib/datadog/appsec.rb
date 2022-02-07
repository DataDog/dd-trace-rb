require 'datadog/appsec/configuration'

module Datadog
  # Namespace for Datadog AppSec instrumentation
  module AppSec
    include Configuration

    def self.writer
      @writer ||= Writer.new
    end
  end
end

# Integrations
require 'datadog/appsec/contrib/rack/integration'
require 'datadog/appsec/contrib/sinatra/integration'
require 'datadog/appsec/contrib/rails/integration'
