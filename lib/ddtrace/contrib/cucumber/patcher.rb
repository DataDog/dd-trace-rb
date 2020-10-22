require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/integration'
require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/cucumber/events'

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
              Datadog::Contrib::Cucumber::Events.new(args[0])

              initialize_without_datadog(*args, &block)
            end
          end
        end
      end
    end
  end
end
