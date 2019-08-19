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

            if datadog_multi_performing?
              # Start Easy span in case Multi is already performing
              easy.datadog_before_request(parent_span: datadog_multi_span)
            end
            handles
          end

          def perform
            if tracer_enabled?
              easy_handles.each do |easy|
                easy.datadog_before_request(parent_span: datadog_multi_span) unless easy.datadog_span_started?
              end
            end
            super
          ensure
            if tracer_enabled? && datadog_multi_performing?
              @datadog_multi_span.finish
              @datadog_multi_span = nil
            end
          end

          private

          def datadog_multi_performing?
            instance_variable_defined?(:@datadog_multi_span) && !@datadog_multi_span.nil?
          end

          def datadog_multi_span
            @datadog_multi_span ||= datadog_configuration[:tracer].trace(
              Ext::SPAN_MULTI_REQUEST,
              service: datadog_configuration[:service_name]
            )

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(@datadog_multi_span, analytics_sample_rate) if analytics_enabled?

            @datadog_multi_span
          end

          def datadog_configuration
            Datadog.configuration[:ethon]
          end

          def tracer_enabled?
            datadog_configuration[:tracer].enabled
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
