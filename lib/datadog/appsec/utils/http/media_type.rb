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
          ParseError = Class.new(StandardError) # steep:ignore IncompatibleAssignment

          WILDCARD = '*'

          # See: https://www.rfc-editor.org/rfc/rfc7230#section-3.2.6
          TOKEN_RE = /[-#$%&'*+.^_`|~A-Za-z0-9]+/.freeze

          # See: https://www.rfc-editor.org/rfc/rfc7231#section-3.1.1.1
          PARAMETER_RE = %r{
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

          class << self
            def json?(media)
              _, subtype = parse(media)
              return false if subtype.nil?

              subtype == 'json' || subtype.end_with?('+json')
            end

            def form_urlencoded?(media)
              _, subtype = parse(media)
              return false if subtype.nil?

              subtype == 'x-www-form-urlencoded'
            end

            private

            def parse(media)
              return if media.nil? || media.empty?

              match = MEDIA_TYPE_RE.match(media)
              return if match.nil?

              type = match['type']
              type&.downcase!

              subtype = match['subtype']
              subtype&.downcase!

              [type, subtype]
            end
          end

          def initialize(media)
            match = MEDIA_TYPE_RE.match(media)
            raise ParseError, media.inspect if match.nil?

            @type = match['type'] || WILDCARD
            @type.downcase!

            @subtype = match['subtype'] || WILDCARD
            @subtype.downcase!

            @parameters = {}

            parameters = match['parameters']
            return if parameters.nil? || parameters.empty?

            parameters.scan(PARAMETER_RE) do |name, unquoted_value, quoted_value|
              # NOTE: Order of unquoted_value and quoted_value does not matter,
              #       as they are mutually exclusive by the regex.
              # @type var value: ::String?
              value = unquoted_value || quoted_value
              next if name.nil? || value.nil?

              # See https://github.com/soutaro/steep/issues/2051
              name.downcase! # steep:ignore NoMethod
              value.downcase!

              # See https://github.com/soutaro/steep/issues/2051
              @parameters[name] = value # steep:ignore ArgumentTypeMismatch
            end
          end

          def to_s
            return "#{@type}/#{@subtype}" if @parameters.empty?

            "#{@type}/#{@subtype};#{@parameters.map { |k, v| "#{k}=#{v}" }.join(";")}"
          end
        end
      end
    end
  end
end
