require 'datadog/security/configuration'

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
require 'datadog/security/contrib/rack/integration'
require 'datadog/security/contrib/sinatra/integration'
require 'datadog/security/contrib/rails/integration'
