require 'ddtrace/configuration/base'

module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      class Settings
        include Datadog::Configuration::Base

        option :analytics_enabled, default: false
        option :analytics_sample_rate, default: 1.0
        option :enabled, default: true
        option :service_name
        option :tracer do |o|
          o.delegate_to { Datadog.tracer }
          o.on_set do |_value|
            log_deprecation_warning(:tracer)
          end
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

        DEPRECATION_WARNING = %(
          Explicitly providing a tracer instance is DEPRECATED.
          It's recommended to not provide an explicit tracer instance
          and let Datadog::Contrib::Configuration::Settings resolve
          the correct tracer internally.
          ).freeze

        include Datadog::Patcher # DEV includes #do_once here. We should move that logic to a generic component.

        def log_deprecation_warning(method_name)
          do_once(method_name) do
            Datadog.logger.warn("#{method_name}:#{DEPRECATION_WARNING}:#{caller.join("\n")}")
          end
        end
      end
    end
  end
end
