require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/grape/ext'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/grape/instrumentation'

module Datadog
  module Contrib
    module Grape
      # Patcher enables patching of 'grape' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          # Patch endpoints
          ::Grape::Endpoint.send(:include, Instrumentation)

          add_pin!

          # Subscribe to ActiveSupport events
          Datadog::Contrib::Grape::Endpoint.subscribe
        end

        def add_pin!
          # Attach a Pin object globally and set the service once
          pin = DeprecatedPin.new(
            get_option(:service_name),
            app: Ext::APP,
            app_type: Datadog::Ext::AppTypes::WEB,
            tracer: -> { get_option(:tracer) }
          )
          pin.onto(::Grape)
        end

        def get_option(option)
          Datadog.configuration[:grape].get_option(option)
        end

        # Implementation of deprecated Pin, which raises warnings when accessed.
        # To be removed when support for Datadog::Pin with Grape is removed.
        class DeprecatedPin < Datadog::Pin
          include Datadog::DeprecatedPin

          DEPRECATION_WARNING = %(
            Use of Datadog::Pin with Grape is DEPRECATED.
            Upgrade to the configuration API using the migration guide here:
            https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0).freeze

          def tracer=(tracer)
            Datadog.configuration[:grape][:tracer] = tracer
          end

          def service_name=(service_name)
            Datadog.configuration[:grape][:service_name] = service_name
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
