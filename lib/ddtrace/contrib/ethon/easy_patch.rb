require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/ethon/ext'
require 'ddtrace/contrib/http_annotation_helper'

module Datadog
  module Contrib
    module Ethon
      # Ethon EasyPatch
      module EasyPatch
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include Datadog::Contrib::HttpAnnotationHelper

          def http_request(url, action_name, options = {})
            load_datadog_configuration_for(url)
            return super unless tracer_enabled?

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
            return super unless tracer_enabled?
            datadog_before_request
            super
          end

          def complete
            return super unless tracer_enabled?
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

          def datadog_before_request(parent_span: nil)
            load_datadog_configuration_for(url)
            @datadog_span = datadog_configuration[:tracer].trace(
              Ext::SPAN_REQUEST,
              service: uri ? service_name(uri.host, datadog_configuration) : datadog_configuration[:service_name],
              span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND
            )
            @datadog_span.parent = parent_span unless parent_span.nil?

            datadog_tag_request

            if datadog_configuration[:distributed_tracing]
              @datadog_original_headers ||= {}
              Datadog::HTTPPropagator.inject!(@datadog_span.context, @datadog_original_headers)
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
            method = 'N/A'
            if instance_variable_defined?(:@datadog_method) && !@datadog_method.nil?
              method = @datadog_method.to_s
            end
            span.resource = method

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            return unless uri
            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, method)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
          end

          def set_span_error_message(message)
            # Sets span error from message, in case there is no exception available
            @datadog_span.status = Datadog::Ext::Errors::STATUS
            @datadog_span.set_tag(Datadog::Ext::Errors::MSG, message)
          end

          def uri
            URI.parse(url)
          # rubocop:disable Lint/HandleExceptions
          rescue URI::InvalidURIError
          end

          def load_datadog_configuration_for(host = :default)
            @datadog_configuration = Datadog.configuration[:ethon, host]
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
