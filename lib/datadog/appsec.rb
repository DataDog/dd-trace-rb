# typed: false

require_relative 'appsec/configuration'
require_relative 'appsec/extensions'

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
require_relative 'appsec/contrib/rack/integration'
require_relative 'appsec/contrib/sinatra/integration'
require_relative 'appsec/contrib/rails/integration'
