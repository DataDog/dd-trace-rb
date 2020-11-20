require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/faraday/ext'
require 'ddtrace/contrib/faraday/connection'
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
              app_type: Datadog::Ext::HTTP::TYPE_OUTBOUND,
              tracer: -> { get_option(:tracer) }
            ).onto(::Faraday)
        end

        def register_middleware!
          ::Faraday::Middleware.register_middleware(ddtrace: Middleware)
        end

        def add_default_middleware!
          if target_version >= Gem::Version.new('1.0.0')
            # Patch the default connection (e.g. +Faraday.get+)
            ::Faraday.default_connection.use(:ddtrace)

            # Patch new connection instances (e.g. +Faraday.new+)
            ::Faraday::Connection.send(:prepend, Connection)
          else
            # Patch the default connection (e.g. +Faraday.get+)
            #
            # We insert our middleware before the 'adapter', which is
            # always the last handler.
            idx = ::Faraday.default_connection.builder.handlers.size - 1
            ::Faraday.default_connection.builder.insert(idx, Middleware)

            # Patch new connection instances (e.g. +Faraday.new+)
            ::Faraday::RackBuilder.send(:prepend, RackBuilder)
          end
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

          def service_name=(service_name)
            Datadog.configuration[:faraday][:service_name] = service_name
          end

          def log_deprecation_warning(method_name)
            do_once(method_name) do
              Datadog.logger.warn("#{method_name}:#{DEPRECATION_WARNING}")
            end
          end
        end
      end
    end
  end
end
