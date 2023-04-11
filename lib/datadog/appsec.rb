# frozen_string_literal: true

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

      def reconfigure(ruleset:)
        appsec_component = components.appsec

        return unless appsec_component

        appsec_component.reconfigure(ruleset: ruleset)
      end

      def reconfigure_lock(&block)
        appsec_component = components.appsec

        return unless appsec_component

        appsec_component.reconfigure_lock(&block)
      end

      private

      def components
        Datadog.send(:components)
      end
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
