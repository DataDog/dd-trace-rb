# frozen_string_literal: true

require "uri"
require "set"

module Datadog
  module Tracing
    module Contrib
      module Utils
        module Quantization
          # Quantization for HTTP resources
          module HTTP
            PLACEHOLDER = "?"

            # taken from Ruby https://github.com/ruby/uri/blob/eaf89cc31619d49e67c64d0b58ea9dc38892d175/lib/uri/rfc3986_parser.rb
            # but adjusted to parse only <scheme>://<host>:<port>/ components
            # and stop there, since we don't care about the path, query string,
            # and fragment components
            RFC3986_URL_BASE = /\A(?<URI>(?<scheme>[A-Za-z][+\-.0-9A-Za-z]*+):(?<hier-part>\/\/(?<authority>(?:(?<userinfo>(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*+)@)?(?<host>(?<IP-literal>\[(?:(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{1,4}?::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h++\.[!$&-.0-;=A-Z_a-z~]++))\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*+))(?::(?<port>\d*+))?)))(?:\/|\z)/.freeze # rubocop:disable Layout/LineLength

            module_function

            def client_resource(method, path, enabled:)
              return method unless enabled && path && !path.empty?

              resource = method.dup
              resource << (+" ").force_encoding(resource.encoding)
              quantized_path = quantize_path(decode_path(path))
              resource << quantized_path.force_encoding(resource.encoding)
            end

            def decode_path(path)
              decoded = String.new(encoding: Encoding::BINARY)
              index = 0

              while index < path.bytesize
                byte = path.getbyte(index)
                break unless byte

                if byte == 37 && index + 2 < path.bytesize
                  high_byte = path.getbyte(index + 1)
                  low_byte = path.getbyte(index + 2)
                  if high_byte && low_byte
                    high = decode_hex_byte(high_byte)
                    low = decode_hex_byte(low_byte)
                    if high && low
                      decoded << high * 16 + low
                      index += 3
                      next
                    end
                  end
                end

                decoded << byte
                index += 1
              end

              decoded.force_encoding(path.encoding)
            end

            def quantize_path(path)
              return path.dup if path.empty?

              slash = (+"/").force_encoding(path.encoding)
              normalized = if path.getbyte(0) == 47
                path
              else
                String.new(encoding: path.encoding) << slash << path
              end

              output = String.new(encoding: path.encoding)
              index = 1
              replacements = 0

              while index < normalized.bytesize
                segment_end = index
                allowed = 0
                digits = 0
                specials = 0

                while segment_end < normalized.bytesize && normalized.getbyte(segment_end) != 47
                  byte = normalized.getbyte(segment_end)
                  break unless byte

                  if byte.between?(48, 57)
                    digits += 1
                  elsif byte.between?(65, 90) || byte.between?(97, 122) || byte == 45 || byte == 95
                    allowed += 1
                  else
                    specials += 1
                  end
                  segment_end += 1
                end

                output << slash
                segment = normalized.byteslice(index, segment_end - index) || String.new(encoding: path.encoding)
                if normalized.getbyte(index) == 118 && allowed == 1 && digits > 0
                  output << segment
                elsif specials > 0 || digits > 0
                  output << (+"*").force_encoding(path.encoding)
                  replacements += 1
                else
                  output << segment
                end

                index = segment_end + 1
              end

              replacements.zero? ? normalized.dup : output
            end

            def url(url, options = {})
              url!(url, options)
            rescue
              placeholder = options[:placeholder] || PLACEHOLDER

              (options[:base] == :exclude) ? placeholder : "#{base_url(url)}/#{placeholder}"
            end

            def base_url(url, options = {})
              if (m = RFC3986_URL_BASE.match(url))
                m[1]
              else
                ""
              end
            end

            def url!(url, options = {})
              options ||= {}

              URI.parse(url).tap do |uri|
                # Format the query string
                if uri.query
                  query = query(uri.query, options[:query])
                  uri.query = ((!query.nil? && query.empty?) ? nil : query)
                end

                # Remove any URI fragments
                uri.fragment = nil unless options[:fragment] == :show

                if options[:base] == :exclude
                  uri.host = nil
                  uri.port = nil
                  uri.scheme = nil
                end
              end.to_s
            end

            def query(query, options = {})
              query!(query, options)
            rescue
              options[:placeholder] || PLACEHOLDER
            end

            def query!(query, options = {})
              options ||= {}
              options[:obfuscate] = {} if options[:obfuscate] == :internal
              options[:show] = options[:show] || (options[:obfuscate] ? :all : [])
              options[:exclude] = options[:exclude] || []

              # Short circuit if query string is meant to exclude everything
              # or if the query string is meant to include everything
              return "" if options[:exclude] == :all

              unless options[:show] == :all && !(options[:obfuscate] && options[:exclude])
                query = collect_query(query, uniq: true) do |key, value|
                  if options[:exclude].include?(key)
                    [nil, nil]
                  else
                    value = (options[:show] == :all || options[:show].include?(key)) ? value : nil
                    [key, value]
                  end
                end
              end

              options[:obfuscate] ? obfuscate_query(query, options[:obfuscate]) : query
            end

            # Iterate over each key value pair, yielding to the block given.
            # Accepts :uniq option, which keeps uniq copies of keys without values.
            # e.g. Reduces "foo&bar=bar&bar=bar&foo" to "foo&bar=bar&bar=bar"
            def collect_query(query, options = {})
              return query unless block_given?

              uniq = options[:uniq].nil? ? false : options[:uniq]
              keys = Set.new

              delims = query.scan(/(^|&|;)/).flatten
              query.split(/[&;]/).collect.with_index do |pairs, i|
                key, value = pairs.split("=", 2)
                key, value = yield(key, value, delims[i])
                if uniq && keys.include?(key)
                  ""
                elsif key && value
                  "#{delims[i]}#{key}=#{value}"
                elsif key
                  "#{delims[i]}#{key}".tap { keys << key }
                # rubocop:disable Lint/DuplicateBranch
                else
                  ""
                end
                # rubocop:enable Lint/DuplicateBranch
              end.join.sub(/^[&;]/, "")
            end

            private_class_method :collect_query

            def decode_hex_byte(byte)
              if byte.between?(48, 57)
                byte - 48
              elsif byte.between?(65, 70)
                byte - 55
              elsif byte.between?(97, 102)
                byte - 87
              end
            end

            private_class_method :decode_hex_byte

            # Scans over the query string and obfuscates sensitive data by
            # replacing matches with an opaque value
            def obfuscate_query(query, options = {})
              options[:regex] = nil if options[:regex] == :internal
              re = options[:regex] || OBFUSCATOR_REGEX
              with = options[:with] || OBFUSCATOR_WITH

              query.gsub(re, with)
            end

            private_class_method :obfuscate_query

            OBFUSCATOR_WITH = "<redacted>"

            # rubocop:disable Layout/LineLength
            OBFUSCATOR_REGEX = %r{
              (?: # JSON-ish leading quote
                 (?:"|%22)?
              )
              (?: # common keys
                 (?:old[-_]?|new_?)?p(?:ass)?w(?:or)?d(?:1|2)? # pw, password variants
                |pass(?:[-_]?phrase)?  # pass, passphrase variants
                |secret
                |(?: # key, key_id variants
                     api[-_]?
                    |private[-_]?
                    |public[-_]?
                    |access[-_]?
                    |secret[-_]?
                 )key(?:[-_]?id)?
                |token
                |consumer[-_]?(?:id|key|secret)
                |sign(?:ed|ature)?
                |auth(?:entication|orization)?
              )
              (?:
                 # '=' query string separator, plus value til next '&' separator
                 (?:\s|%20)*(?:=|%3D)[^&]+
                 # JSON-ish '": "somevalue"', key being handled with case above, without the opening '"'
                |(?:"|%22)                                     # closing '"' at end of key
                 (?:\s|%20)*(?::|%3A)(?:\s|%20)*               # ':' key-value spearator, with surrounding spaces
                 (?:"|%22)                                     # opening '"' at start of value
                 (?:%2[^2]|%[^2]|[^"%])+                       # value
                 (?:"|%22)                                     # closing '"' at end of value
              )
             |(?: # other common secret values
                 bearer(?:\s|%20)+[a-z0-9._-]+
                |token(?::|%3A)[a-z0-9]{13}
                |gh[opsu]_[0-9a-zA-Z]{36}
                |ey[I-L](?:[\w=-]|%3D)+\.ey[I-L](?:[\w=-]|%3D)+(?:\.(?:[\w.+/=-]|%3D|%2F|%2B)+)?
                |-{5}BEGIN(?:[a-z\s]|%20)+PRIVATE(?:\s|%20)KEY-{5}[^-]+-{5}END(?:[a-z\s]|%20)+PRIVATE(?:\s|%20)KEY(?:-{5})?(?:\n|%0A)?
                |(?:ssh-(?:rsa|dss)|ecdsa-[a-z0-9]+-[a-z0-9]+)(?:\s|%20)*(?:[a-z0-9/.+]|%2F|%5C|%2B){100,}(?:=|%3D)*(?:(?:\s+)[a-z0-9._-]+)?
              )
            }ix.freeze
            # rubocop:enable Layout/LineLength
          end
        end
      end
    end
  end
end
