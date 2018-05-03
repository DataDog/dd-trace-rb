require 'ddtrace/contrib/configuration/options'

module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      class Settings
        include Options

        option :service_name
        option :tracer, default: Datadog.tracer

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
      end
    end
  end
end
