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

        def patched?
          done?(:dalli)
        end

        def patch
          do_once(:dalli) do
            begin
              add_pin!
              Instrumentation.patch!
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Dalli integration: #{e}")
            end
          end
        end

        def add_pin!
          Pin
            .new(
              get_option(:service_name),
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::CACHE,
              tracer: get_option(:tracer)
            ).onto(::Dalli)
        end

        def get_option(option)
          Datadog.configuration[:dalli].get_option(option)
        end
      end
    end
  end
end
