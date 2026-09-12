# frozen_string_literal: true

require_relative "utils/quantization/http"
require_relative "../../core/telemetry/logger"

module Datadog
  module Tracing
    module Contrib
      # Contains methods helpful for tracing/annotating HTTP request libraries
      module HttpAnnotationHelper
        def service_name(hostname, configuration_options, pin = nil)
          return hostname if configuration_options[:split_by_domain]
          return pin[:service_name] if pin && pin[:service_name]

          configuration_options[:service_name]
        end

        # Builds the resource name for an HTTP client span.
        #
        # Defaults to the bare HTTP method. When
        # `Datadog.configuration.tracing.http_client_resource_name_quantize` is enabled,
        # a quantized request path is appended, eg. `GET /users/?`.
        def http_client_resource_name(http_method, path)
          resource = http_method.to_s.upcase
          return resource unless Datadog.configuration.tracing.http_client_resource_name_quantize

          # Some clients expose the query string as part of the path; it is reported
          # separately and must not reach the resource name.
          "#{resource} #{Contrib::Utils::Quantization::HTTP.path(path.to_s.split("?", 2).first)}"
        rescue => e
          # A path carrying invalid byte sequences would otherwise raise while being
          # matched, so fall back to the unquantized resource name.
          Datadog.logger.error("error building http client resource name: #{e.class}: #{e.message}")
          Datadog::Core::Telemetry::Logger.report(e)
          http_method.to_s.upcase
        end
      end
    end
  end
end
