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
          def self.included(base)
            base.send(:include, ClassMethods)
          end

          # ClassMethods - patching the HTTParty mixin
          module ClassMethods
            # Configures dd-tracer for the specific client
            #
            #   class Foo
            #     include HTTParty
            #     dd_options service_name: 'foo-client'
            #   end
            def dd_options(options = nil)
              default_options[:dd_options] = options
            end
          end
        end
      end
    end
  end
end
