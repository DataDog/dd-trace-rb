require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/httprb/instrumentation'

module Datadog
  module Contrib
    # Datadog Httprb integration.
    module Httprb
      # Patcher enables patching of 'httprb' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:httprb)
        end

        def target_version
          Integration.version
        end
        # patch applies our patch
        def patch
          do_once(:httprb) do
            begin
              Events.subscribe!
              ::HTTP::Options.send(:include, Instrumentation)
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply httprb integration: #{e}")
            end
          end
        end

        # def register_feature!
        #   ::HTTP::Options.register_feature(:datadog_wrap, Datadog::Contrib::Httprb::DatadogWrap)
        # end
      end
    end
  end
end
