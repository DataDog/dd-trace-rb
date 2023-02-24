require_relative 'appsec/configuration'
require_relative 'appsec/extensions'

module Datadog
  # Namespace for Datadog AppSec instrumentation
  module AppSec
    include Configuration

    class << self
      def enabled?
        Datadog.configuration.appsec.enabled
      end

      def processor
        appsec_component = components.appsec

        appsec_component.processor if appsec_component
      end

      private

      def components
        Datadog.send(:components)
      end
    end

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

require_relative 'appsec/autoload'
