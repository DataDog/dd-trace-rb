require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/integration'
require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'

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

          Datadog::Pin.new(
            Datadog.configuration[:cucumber][:service_name],
            app: Datadog::Contrib::Cucumber::Ext::APP,
            app_type: Datadog::Ext::AppTypes::TEST,
            tracer: -> { Datadog.configuration[:cucumber][:tracer] }
          ).onto(::Cucumber)

          patch_cucumber_runtime
        end

        def patch_cucumber_runtime
          require 'ddtrace/contrib/cucumber/formatter'

          ::Cucumber::Runtime.class_eval do
            attr_reader :datadog_formatter

            alias_method :formatters_without_datadog, :formatters
            Datadog::Patcher.without_warnings do
              remove_method :formatters
            end

            def formatters
              @datadog_formatter ||= Datadog::Contrib::Cucumber::Formatter.new(@configuration)
              [@datadog_formatter] + formatters_without_datadog
            end
          end
        end
      end
    end
  end
end
