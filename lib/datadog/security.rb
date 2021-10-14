require 'datadog/security/configuration'
require 'datadog/security/writer'

module Datadog
  # Namespace for Datadog Security instrumentation
  module Security
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
