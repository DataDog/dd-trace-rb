require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/dalli/ext'
require 'ddtrace/contrib/dalli/instrumentation'

module Datadog
  module Contrib
    module Dalli
      # Patcher enables patching of 'dalli' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          add_pin!
          ::Dalli::Server.send(:include, Instrumentation)
        end

        # DEPRECATED: Only kept for users still using `Dalli.datadog_pin` to configure.
        #             Replaced by configuration API, i.e. `c.use :dalli`.
        def add_pin!
          DeprecatedPin
            .new(
              get_option(:service_name),
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::CACHE,
              tracer: -> { get_option(:tracer) }
            ).onto(::Dalli)
        end

        def get_option(option)
          Datadog.configuration[:dalli].get_option(option)
        end

        # Implementation of deprecated Pin, which raises warnings when accessed.
        # To be removed when support for Datadog::Pin with Dalli is removed.
        class DeprecatedPin < Datadog::Pin
          include Datadog::DeprecatedPin

          DEPRECATION_WARNING = %(
            Use of Datadog::Pin with Dalli is DEPRECATED.
            Upgrade to the configuration API using the migration guide here:
            https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0).freeze

          def service_name=(service_name)
            Datadog.configuration[:dalli][:service_name] = service_name
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
