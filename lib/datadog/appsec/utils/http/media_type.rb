# frozen_string_literal: true

module Datadog
  module AppSec
    module Utils
      module HTTP
        # Implementation of media type for HTTP headers
        #
        # See:
        # - https://www.rfc-editor.org/rfc/rfc7231#section-5.3.1
        # - https://www.rfc-editor.org/rfc/rfc7231#section-5.3.2
        class MediaType
          class ParseError < ::StandardError
          end

          # See: https://www.rfc-editor.org/rfc/rfc7230#section-3.2.6
          TOKEN_RE = /[-#$%&'*+.^_`|~A-Za-z0-9]+/.freeze

          # See: https://www.rfc-editor.org/rfc/rfc7231#section-3.1.1.1
          PARAMETER_RE = %r{ # rubocop:disable Style/RegexpLiteral
            (?:
              (?<parameter_name>#{TOKEN_RE})
              =
              (?:
                (?<parameter_value>#{TOKEN_RE})
                |
                "(?<parameter_value>[^"]+)"
              )
            )
          }ix.freeze

          # See: https://www.rfc-editor.org/rfc/rfc7231#section-3.1.1.1
          MEDIA_TYPE_RE = %r{
            \A
            (?<type>#{TOKEN_RE})/(?<subtype>#{TOKEN_RE})
            (?<parameters>
              (?:
                \s*;\s*
                #{PARAMETER_RE}
              )*
            )
            \Z
          }ix.freeze

          attr_reader :type, :subtype, :parameters

          def initialize(media_type)
            media_type_match = MEDIA_TYPE_RE.match(media_type)

            raise ParseError, media_type.inspect if media_type_match.nil?

            @type = media_type_match['type'].downcase
            @subtype = media_type_match['subtype'].downcase
            @parameters = {}

            parameters = media_type_match['parameters']
            return if parameters.nil?

            parameters.scan(PARAMETER_RE) do |name, unquoted_value, quoted_value|
              # NOTE: Order of unquoted_value and quoted_value does not matter,
              #       as they are mutually exclusive by the regex.
              value = unquoted_value || quoted_value
              next if name.nil? || value.nil?

              @parameters[name.downcase] = value.downcase
            end
          end

          def to_s
            s = +"#{@type}/#{@subtype}"
            s << ';' << @parameters.map { |k, v| "#{k}=#{v}" }.join(';') if @parameters.count > 0
            s
          end
        end
      end
    end
  end
end
