require 'ddtrace/contrib/elasticsearch/quantize'

module Datadog
  module Contrib
    # Contains methods helpful for tracing/annotating HTTP request libraries
    module HttpAnnotationHelper
      def service_name(hostname, configuration_options)
        configuration_options[:split_by_domain] ? hostname : configuration_options[:service_name]
      end

      # [WIP]
      # resource_name 
      # should_quantize attempts to replace the following
      #   sequence of decimal digits of any length
      #   sequence of hexadecimal digits of 16 or more characters (ignoring hyphens)
      #
      # TODO: 
      # 1. Generalize Quantize.format_url into common(contrib?) utils
      # 2. Does Quantize.format_url handle hexadecimal currently? I don't believe so?
      # 3. Should this be based more strictly on implementation in dotnet? 
      #    https://github.com/DataDog/dd-trace-dotnet/blob/4db4c05cef64eb2930ec72bbfb20c806593b83ee/src/Datadog.Trace.ClrProfiler.Managed/ScopeFactory.cs#L105
      # 4. Compare performance tradeoffs and strictness/approaches of detecting hexadecimal strings of certain length, 
      #    either by the dotnet approach or by regex
      #    https://github.com/open-telemetry/opentelemetry-ruby/blob/94b4207637d69a43d18fc54916b7067bda0a1678/instrumentation/mysql2/lib/opentelemetry/instrumentation/mysql2/patches/client.rb#L38
      def resource_name(method, hostname, uri, should_quantize = false, should_use_host = false)
        if should_quantize 
          # TODO: update to wrap this with some rough code to mimic the dotnet hexademical work
          quantized_path = Datadog::Contrib::Elasticsearch::Quantize.format_url(uri.path)

          if should_use_host

            # keep only host and path.
            # remove scheme, userinfo, query, and fragment.
            return "#{method} #{hostname}#{quantized_path}"
          end

          # keep only path.
          # remove scheme, userinfo, query, and fragment.
          return "#{method} #{quantized_path}"
        end

        # Can we formalize quantization implementation in datadog-agent and simply use full url?
        # Additional Obfuscation code

        # default behavior returns just method
        should_use_host ? "#{method} #{hostname}" : method
      end
    end
  end
end
