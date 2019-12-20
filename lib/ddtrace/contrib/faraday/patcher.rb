require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/faraday/ext'
require 'ddtrace/contrib/faraday/rack_builder'

module Datadog
  module Contrib
    module Faraday
      # Patcher enables patching of 'faraday' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/faraday/middleware'

          add_pin!
          register_middleware!
          add_default_middleware!
        end

        def add_pin!
          DeprecatedPin
            .new(
              get_option(:service_name),
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::WEB,
              tracer: get_option(:tracer)
            ).onto(::Faraday)
        end

        def register_middleware!
          ::Faraday::Middleware.register_middleware(ddtrace: Middleware)
        end

        def add_default_middleware!
          ::Faraday::RackBuilder.send(:prepend, RackBuilder)
        end

        def get_option(option)
          Datadog.configuration[:faraday].get_option(option)
        end

        # Implementation of deprecated Pin, which raises warnings when accessed.
        # To be removed when support for Datadog::Pin with Faraday is removed.
        class DeprecatedPin < Datadog::Pin
          include Datadog::DeprecatedPin

          DEPRECATION_WARNING = %(
            Use of Datadog::Pin with Faraday is DEPRECATED.
            Upgrade to the configuration API using the migration guide here:
            https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0).freeze

          def tracer=(tracer)
            Datadog.configuration[:faraday][:tracer] = tracer
          end

          def service_name=(service_name)
            Datadog.configuration[:faraday][:service_name] = service_name
          end

          def log_deprecation_warning(method_name)
            do_once(method_name) do
              Datadog::Logger.log.warn("#{method_name}:#{DEPRECATION_WARNING}")
            end
          end
        end
      end
    end
  end
end
