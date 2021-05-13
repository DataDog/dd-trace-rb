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
      # 3. Should this be based more strictly on dotnet  or shoud we remove any segment with a single digit?
      #    removing any segment with a digit would be similar to what we do for elasticsearch quantization
      #    https://github.com/DataDog/dd-trace-dotnet/blob/4db4c05cef64eb2930ec72bbfb20c806593b83ee/src/Datadog.Trace.ClrProfiler.Managed/ScopeFactory.cs#L105
      # 4. Compare performance tradeoffs and strictness/approaches of detecting hexadecimal strings of certain length,
      #    either by the dotnet approach or by regex
      #    https://github.com/open-telemetry/opentelemetry-ruby/blob/94b4207637d69a43d18fc54916b7067bda0a1678/instrumentation/mysql2/lib/opentelemetry/instrumentation/mysql2/patches/client.rb#L38
      def resource_name(method, hostname, uri_path, should_quantize = false, should_use_host = false) # rubocop:disable Metrics/PerceivedComplexity
        if should_quantize

          quantized_path = uri_path
          path_to_build = ''

          unless quantized_path == '' || quantized_path.nil? || (quantized_path.length == 1 && quantized_path[0] == '/')
            previous_index = 0
            current_index = nil
            segment_length = nil

            while current_index != -1
              current_index = quantized_path.index('/', previous_index)

              if current_index.nil? # rubocop:disable Metrics/BlockNesting
                current_index = -1

                segment_length = quantized_path.length - previous_index
              else
                segment_length = current_index - previous_index
              end

              if path_to_build << identifier_segment?(quantized_path, previous_index, segment_length) # rubocop:disable Metrics/BlockNesting
                '?'
              else
                quantized_path[previous_index, segment_length]
              end

              path_to_build << '/' if current_index != -1 # rubocop:disable Metrics/BlockNesting

              previous_index = current_index + 1
            end
          end

          path_to_build << '/' if quantized_path.length == 1 && quantized_path[0] == '/'

          if should_use_host

            # keep only host and path.
            # remove scheme, userinfo, query, and fragment.
            return "#{method} #{hostname}#{path_to_build}"
          end

          if path_to_build
            # keep only path.
            # remove scheme, userinfo, query, and fragment.
            return "#{method} #{path_to_build}"
          end
        end

        # Can we formalize quantization implementation in datadog-agent and simply use full url?
        # Should we add additional Obfuscation code for known other cases

        # default behavior returns just method
        should_use_host ? "#{method} #{hostname}" : method
      end

      private

      def identifier_segment?(quantized_path, previous_index, segment_length)
        return false if segment_length == 0

        last_index = previous_index + segment_length
        contains_number = false

        loop_index = previous_index

        while (loop_index < last_index) && (loop_index < quantized_path.length)
          char = quantized_path[loop_index]

          if char >= '0' && char <= '9'
            contains_number = true
            loop_index += 1

            next
          elsif (char >= 'a' && char <= 'f') || (char >= 'A' && char <= 'F')
            return false if segment_length < 16

            loop_index += 1

            next
          elsif char == '-'
            loop_index += 1

            next
          else
            return false
          end
        end

        contains_number
      end
    end
  end
end
