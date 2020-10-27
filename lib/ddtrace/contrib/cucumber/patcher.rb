require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/cucumber/instrumentation'

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
          require 'ddtrace/ext/ci'
          require 'ddtrace/ext/integration'

          Datadog::Pin.new(
            Datadog.configuration[:cucumber][:service_name],
            app: Ext::APP,
            app_type: Datadog::Ext::AppTypes::TEST,
            tags: Datadog::Ext::CI.tags(ENV).merge(Datadog.configuration.tags),
            tracer: -> { Datadog.configuration[:cucumber][:tracer] }
          ).onto(::Cucumber)

          ::Cucumber::Runtime.send(:include, Instrumentation)
        end
      end
    end
  end
end
