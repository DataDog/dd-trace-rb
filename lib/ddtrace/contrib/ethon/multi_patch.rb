require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/ethon/ext'

module Datadog
  module Contrib
    module Ethon
      # Ethon MultiPatch
      module MultiPatch
        def self.included(base)
          # No need to prepend here since add method is included into Multi class
          base.send(:include, InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def add(easy)
            handles = super(easy)
            return handles if handles.nil? || !tracer_enabled?

            easy.datadog_before_request
            handles
          end

          private

          def datadog_configuration
            Datadog.configuration[:ethon]
          end

          def tracer_enabled?
            datadog_configuration[:tracer].enabled
          end
        end
      end
    end
  end
end
