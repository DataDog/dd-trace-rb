require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/rest_client/ext'

module Datadog
  module Contrib
    module HTTParty
      module Instrumentation
        # HTTParty Helpers
        module Helpers
          DATADOG_TRACER_OPTIONS_KEY = :ddtrace_options

          def self.included(base)
            base.send(:include, ClassMethods)
          end

          # ClassMethods - patching the HTTParty mixin
          module ClassMethods
            # Configures dd-tracer for the specific client
            #
            #   class Foo
            #     include HTTParty
            #     ddtrace_options service_name: 'foo-client'
            #   end
            define_method(DATADOG_TRACER_OPTIONS_KEY) do |options = nil|
              default_options[DATADOG_TRACER_OPTIONS_KEY] = options
            end
          end
        end
      end
    end
  end
end
