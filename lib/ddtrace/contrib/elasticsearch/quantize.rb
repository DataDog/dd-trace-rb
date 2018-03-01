module Datadog
  module Contrib
    module Elasticsearch
      # Quantize contains ES-specific resource quantization tools.
      module Quantize
        EXCLUDE_KEYS = [].freeze
        SHOW_KEYS = [:_index, :_type, :_id].freeze
        PLACEHOLDER = '?'.freeze

        ID_REGEXP = %r{\/([0-9]+)([\/\?]|$)}
        ID_PLACEHOLDER = '/?\2'.freeze

        INDEX_REGEXP = /[0-9]{2,}/
        INDEX_PLACEHOLDER = '?'.freeze

        module_function

        # Very basic quantization, complex processing should be done in the agent
        def format_url(url)
          quantized_url = url.gsub(ID_REGEXP, ID_PLACEHOLDER)
          quantized_url.gsub(INDEX_REGEXP, INDEX_PLACEHOLDER)
        end

        def format_body(body, exclude = [], show = [])
          # Determine if bulk query or not, based on content
          statements = body.end_with?("\n") ? body.split("\n") : [body]

          # Attempt to parse each
          statements.collect do |s|
            begin
              JSON.dump(format_statement(JSON.parse(s), EXCLUDE_KEYS, SHOW_KEYS))
            rescue JSON::ParserError
              # If it can't parse/dump, don't raise an error.
              PLACEHOLDER
            end
          end.join("\n")
        end

        def format_statement(statement, exclude = [], show = [])
          case statement
          when Hash
            statement.each_with_object({}) do |(key, value), quantized|
              if show == :all || show.include?(key.to_sym)
                quantized[key] = value
              elsif !exclude.include?(key.to_sym)
                quantized[key] = format_value(value, exclude, show)
              end
            end
          else
            format_value(statement, exclude, show)
          end
        end

        def format_value(value, exclude = [], show = [])
          case value
          when Hash
            format_statement(value, exclude, show)
          when Array
            format_value(value.first, exclude, show)
          else
            show == :all ? value : PLACEHOLDER
          end
        end
      end
    end
  end
end
