# typed: false
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/metadata'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/ethon/ext'

module Datadog
  module Contrib
    module Ethon
      # Ethon MultiPatch
      module MultiPatch
        def self.included(base)
          # No need to prepend here since add method is included into Multi class
          base.include(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def add(easy)
            handles = super
            return handles unless handles && Datadog::Tracing.enabled?

            if datadog_multi_performing?
              # Start Easy span in case Multi is already performing
              easy.datadog_before_request(continue_from: datadog_multi_trace_digest)
            end
            handles
          end

          def perform
            if Datadog::Tracing.enabled?
              easy_handles.each do |easy|
                easy.datadog_before_request(continue_from: datadog_multi_trace_digest) unless easy.datadog_span_started?
              end
            end
            super
          ensure
            if Datadog::Tracing.enabled? && datadog_multi_performing?
              @datadog_multi_span.finish
              @datadog_multi_span = nil
              @datadog_multi_trace_digest = nil
            end
          end

          private

          def datadog_multi_performing?
            instance_variable_defined?(:@datadog_multi_span) && !@datadog_multi_span.nil?
          end

          def datadog_multi_trace_digest
            return unless datadog_multi_span

            @datadog_multi_trace_digest
          end

          def datadog_multi_span
            return @datadog_multi_span if datadog_multi_performing?

            @datadog_multi_span = Datadog::Tracing.trace(
              Ext::SPAN_MULTI_REQUEST,
              service: datadog_configuration[:service_name]
            )
            @datadog_multi_trace_digest = Datadog::Tracing.active_trace.to_digest

            @datadog_multi_span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            @datadog_multi_span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_MULTI_REQUEST)

            # Tag as an external peer service
            @datadog_multi_span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, @datadog_multi_span.service)

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(@datadog_multi_span, analytics_sample_rate) if analytics_enabled?

            @datadog_multi_span
          end

          def datadog_configuration
            Datadog::Tracing.configuration[:ethon]
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
