require 'ddtrace/configuration/base'

module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      class Settings
        include Datadog::Configuration::Base

        option :analytics_enabled, default: false
        option :analytics_sample_rate, default: 1.0
        option :service_name
        option :tracer do |o|
          o.delegate_to { Datadog.tracer }
        end

        def configure(options = {})
          self.class.options.dependency_order.each do |name|
            self[name] = options[name] if options.key?(name)
          end

          yield(self) if block_given?
        end

        def [](name)
          respond_to?(name) ? send(name) : get_option(name)
        end

        def []=(name, value)
          respond_to?("#{name}=") ? send("#{name}=", value) : set_option(name, value)
        end
      end
    end
  end
end
