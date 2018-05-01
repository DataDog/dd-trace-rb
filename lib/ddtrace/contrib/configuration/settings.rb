module Datadog
  module Contrib
    module Configuration
      # Common settings for all integrations
      class Settings
        attr_reader \
          :service_name,
          :tracer

        attr_writer \
          :service_name,
          :tracer

        def initialize(options = {})
          configure(default_options.merge(options))
        end

        def reset_options!
          configure(default_options)
        end

        def configure(options = {})
          options.each { |k, v| self[k] = v }
          yield(self) if block_given?
        end

        def [](param)
          send(param)
        end

        def []=(param, value)
          send("#{param}=", value)
        end

        def default_options
          {
            service_name: nil,
            tracer: Datadog.tracer
          }
        end
      end
    end
  end
end
