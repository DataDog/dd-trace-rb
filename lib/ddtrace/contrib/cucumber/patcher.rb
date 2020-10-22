require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/ext/integration'
require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/cucumber/events'
require 'ddtrace/contrib/cucumber/ext'

module Datadog
  module Contrib
    module Cucumber
      # Patcher enables patching of 'cucumber' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/pin'

          patch_cucumber_runtime
        end

        def patch_cucumber_runtime
          ::Cucumber::Runtime.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args, &block)
              service = Datadog.configuration[:cucumber][:service_name]

              pin = Datadog::Pin.new(
                service,
                app: Datadog::Contrib::Cucumber::Ext::APP,
                app_type: Datadog::Ext::AppTypes::TEST,
                tracer: -> { Datadog.configuration[:cucumber][:tracer] }
              )
              pin.onto(self)

              Datadog::Contrib::Cucumber::Events.new(args[0], pin)

              initialize_without_datadog(*args, &block)
            end

            def datadog_configuration
              Datadog.configuration[:cucumber]
            end
          end
        end
      end
    end
  end
end
