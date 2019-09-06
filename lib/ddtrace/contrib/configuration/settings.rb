require 'ddtrace/environment'
require 'ddtrace/configuration/options'
require 'ddtrace/contrib/configuration/integrations'

module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      class Settings
        extend Datadog::Environment::Helpers
        include Datadog::Configuration::Options
        include Integrations

        option :service_name
        option :tracer,
               default: -> { Datadog.tracer },
               lazy: true
        option :analytics_enabled, default: false
        option :analytics_sample_rate, default: 1.0

        def initialize(options = {})
          configure(options)
        end

        def configure(options = {})
          self.class.options.dependency_order.each do |name|
            self[name] = options.fetch(name, self[name])
          end

          yield(self) if block_given?
        end

        def [](name)
          respond_to?(name) ? send(name) : get_option(name)
        end

        def []=(name, value)
          respond_to?("#{name}=") ? send("#{name}=", value) : set_option(name, value)
        end

        def to_h
          integrations_hash.merge(options_hash)
        end

        def reset!
          reset_options!
          reset_integrations!
        end
      end
    end
  end
end
