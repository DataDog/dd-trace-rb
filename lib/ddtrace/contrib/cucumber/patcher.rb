require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/cucumber/instrumentation'

module Datadog
  module Contrib
    module Cucumber
      # Patcher enables patching of 'cucumber' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:cucumber)
        end

        def target_version
          Integration.version
        end

        # patch applies our patch
        def patch
          do_once(:cucumber) do
            require 'ddtrace/ext/ci'
            require 'ddtrace/ext/integration'

            begin
              Datadog::Pin.new(
                Datadog.configuration[:cucumber][:service_name],
                app: Datadog::Contrib::Cucumber::Ext::APP,
                app_type: Datadog::Ext::AppTypes::TEST,
                tags: Datadog::Ext::CI.tags(ENV).merge(Datadog.configuration.tags),
                tracer: -> { Datadog.configuration[:cucumber][:tracer] }
              ).onto(::Cucumber)

              ::Cucumber::Runtime.send(:include, Instrumentation)
            rescue StandardError => e
              Datadog::Logger.error("Unable to apply cucumber integration: #{e}")
            end
          end
        end
      end
    end
  end
end
