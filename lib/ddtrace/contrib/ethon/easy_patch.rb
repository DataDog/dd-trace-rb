# typed: false
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/metadata'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/ethon/ext'
require 'ddtrace/contrib/http_annotation_helper'

module Datadog
  module Contrib
    module Ethon
      # Ethon EasyPatch
      module EasyPatch
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        # rubocop:disable Metrics/ModuleLength
        module InstanceMethods
          include Datadog::Contrib::HttpAnnotationHelper

          def http_request(url, action_name, options = {})
            load_datadog_configuration_for(url)
            return super unless Datadog::Tracing.enabled?

            # It's tricky to get HTTP method from libcurl
            @datadog_method = action_name.to_s.upcase
            super
          end

          def headers=(headers)
            # Store headers to call this method again when span is ready
            @datadog_original_headers = headers
            super
          end

          def perform
            load_datadog_configuration_for(url)
            return super unless Datadog::Tracing.enabled?

            datadog_before_request
            super
          end

          def complete
            return super unless Datadog::Tracing.enabled?

            begin
              response_options = mirror.options
              response_code = (response_options[:response_code] || response_options[:code]).to_i
              if response_code.zero?
                return_code = response_options[:return_code]
                message = return_code ? ::Ethon::Curl.easy_strerror(return_code) : 'unknown reason'
                set_span_error_message("Request has failed: #{message}")
              else
                @datadog_span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response_code)
                if Datadog::Ext::HTTP::ERROR_RANGE.cover?(response_code)
                  set_span_error_message("Request has failed with HTTP error: #{response_code}")
                end
              end
            ensure
              @datadog_span.finish
              @datadog_span = nil
            end
            super
          end

          def reset
            super
          ensure
            @datadog_span = nil
            @datadog_method = nil
            @datadog_original_headers = nil
            @datadog_configuration = nil
          end

          # Starts or retrieves the already started Easy request span.
          #
          # When tracing in Multi request context, child spans for each Easy
          # request are created early, and then finished as their HTTP response
          # becomes available. Because many Easy requests are open at the same time,
          # many Datadog::Spans are also open at the same time. To avoid each separate
          # Easy request becoming the parented to the previous open request we set
          # the +parent_span+ parameter with the parent Multi span. This correctly
          # assigns all open Easy spans to the currently executing Multi context.
          #
          # @param [Datadog::Span] continue_from the Multi span, if executing in a Multi context.
          def datadog_before_request(continue_from: nil)
            load_datadog_configuration_for(url)

            trace_options = continue_from ? { continue_from: continue_from } : {}
            @datadog_span = Datadog::Tracing.trace(
              Ext::SPAN_REQUEST,
              service: uri ? service_name(uri.host, datadog_configuration) : datadog_configuration[:service_name],
              span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND,
              **trace_options
            )
            datadog_trace = Datadog::Tracing.active_trace

            datadog_tag_request

            if datadog_configuration[:distributed_tracing]
              @datadog_original_headers ||= {}
              Datadog::HTTPPropagator.inject!(datadog_trace, @datadog_original_headers)
              self.headers = @datadog_original_headers
            end
          end

          def datadog_span_started?
            instance_variable_defined?(:@datadog_span) && !@datadog_span.nil?
          end

          private

          attr_reader :datadog_configuration

          def datadog_tag_request
            span = @datadog_span
            method = Ext::NOT_APPLICABLE_METHOD
            method = @datadog_method.to_s if instance_variable_defined?(:@datadog_method) && !@datadog_method.nil?
            span.resource = method
            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            this_uri = uri
            return unless this_uri

            span.set_tag(Datadog::Ext::HTTP::URL, this_uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, method)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, this_uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, this_uri.port)

            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, this_uri.host)
          end

          def set_span_error_message(message)
            # Sets span error from message, in case there is no exception available
            @datadog_span.status = Datadog::Ext::Errors::STATUS
            @datadog_span.set_tag(Datadog::Ext::Errors::MSG, message)
          end

          def uri
            URI.parse(url)
          rescue URI::InvalidURIError
          end

          def load_datadog_configuration_for(host = :default)
            @datadog_configuration = Datadog::Tracing.configuration[:ethon, host]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
        # rubocop:enable Metrics/ModuleLength
      end
    end
  end
end
