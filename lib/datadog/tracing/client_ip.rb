# typed: true

require 'ipaddr'

require_relative '../core/configuration'
require_relative 'metadata/ext'
require_relative 'span'

module Datadog
  module Tracing
    # Common functions for supporting the `http.client_ip` span attribute.
    module ClientIp
      DEFAULT_IP_HEADERS_NAMES = %w[
        x-forwarded-for
        x-real-ip
        x-client-ip
        x-forwarded
        x-cluster-client-ip
        forwarded-for
        forwarded
        via
        true-client-ip
      ].freeze

      # A collection of headers.
      class HeaderCollection
        # Gets a single value of the header with the given name, case insensitive.
        #
        # @param [String] header_name Name of the header to get the value of.
        # @returns [String, nil] A single value of the header, or nil if the header with
        #   the given name is missing from the collection.
        def get(header_name)
          nil
        end

        def self.from_hash(hash)
          HashHeaderCollection.new(hash)
        end
      end

      # Sets the `http.client_ip` tag on the given span.
      #
      # This function respects the user's settings: if they disable the client IP tagging,
      # or provide a different IP header name.
      #
      # @param [Span] span The span that's associated with the request.
      # @param [HeaderCollection, #get, nil] headers A collection with the request headers.
      # @param [String, nil] remote_ip The remote IP the request associated with the span is sent to.
      def self.set_client_ip_tag(span, headers, remote_ip)
        return if configuration.disabled

        ip = client_address_from_request(headers, remote_ip)
        if !configuration.header_name && ip.nil?
          header_names = ip_headers(headers).keys
          span.set_tag(TAG_MULTIPLE_IP_HEADERS, header_names.join(',')) unless header_names.empty?
          return
        end

        unless valid_ip?(ip)
          ip = extract_ip_from_full_address(ip)
          return unless valid_ip?(ip)
        end
        ip = strip_zone_specifier(ip) if valid_ipv6?(ip)

        span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, ip)
      end

      TAG_MULTIPLE_IP_HEADERS = '_dd.multiple-ip-headers'.freeze

      # A header collection implementation that looks up headers in a Hash.
      class HashHeaderCollection < HeaderCollection
        def initialize(hash)
          super()
          @hash = hash.transform_keys(&:downcase)
        end

        def get(header_name)
          @hash[header_name.downcase]
        end
      end

      def self.ip_headers(headers)
        return {} unless headers

        {}.tap do |result|
          DEFAULT_IP_HEADERS_NAMES.each do |name|
            value = headers.get(name)
            next if value.nil?

            result[name] = value
          end
        end
      end

      def self.client_address_from_request(headers, remote_ip)
        return headers.get(configuration.header_name) if configuration.header_name && headers

        ip_values_from_headers = ip_headers(headers).values
        case ip_values_from_headers.size
        when 0
          remote_ip
        when 1
          ip_values_from_headers.first
        end
      end

      def self.strip_zone_specifier(ipv6)
        if /\A(.*?)%.*/ =~ ipv6
          return Regexp.last_match(1)
        end

        ipv6
      end

      # Extracts the IP part from a full address (`ipv4:port` or `[ipv6]:port`).
      #
      # @param [String] address Full address to split
      # @returns [String] The IP part of the full address.
      def self.extract_ip_from_full_address(address)
        if /\A\[(.*)\]:\d+\Z/ =~ address
          return Regexp.last_match(1)
        end

        if /\A(.*):\d+\Z/ =~ address
          return Regexp.last_match(1)
        end

        address
      end

      def self.configuration
        Datadog.configuration.tracing.client_ip
      end

      # Determines whether the given IP is valid.
      #
      # @param [String] ip The IP to validate.
      # @returns [Boolean]
      def self.valid_ip?(ip)
        valid_ipv4?(ip) || valid_ipv6?(ip)
      end

      # --- Section vendored from the ipaddress gem --- #

      # rubocop:disable Layout/LineLength, Style/SpecialGlobalVars

      #
      # Checks if the given string is a valid IPv4 address
      #
      # Example:
      #
      #   IPAddress::valid_ipv4? "2002::1"
      #     #=> false
      #
      #   IPAddress::valid_ipv4? "172.16.10.1"
      #     #=> true
      #
      # Vendored from `ipaddress` gem from file 'lib/ipaddress.rb', line 198.
      def self.valid_ipv4?(addr)
        if /^(0|[1-9]{1}\d{0,2})\.(0|[1-9]{1}\d{0,2})\.(0|[1-9]{1}\d{0,2})\.(0|[1-9]{1}\d{0,2})$/ =~ addr
          return $~.captures.all? { |i| i.to_i < 256 }
        end

        false
      end

      #
      # Checks if the given string is a valid IPv6 address
      #
      # Example:
      #
      #   IPAddress::valid_ipv6? "2002::1"
      #     #=> true
      #
      #   IPAddress::valid_ipv6? "2002::DEAD::BEEF"
      #     #=> false
      #
      # Vendored from `ipaddress` gem from file 'lib/ipaddress.rb', line 230.
      def self.valid_ipv6?(addr)
        # https://gist.github.com/cpetschnig/294476
        # http://forums.intermapper.com/viewtopic.php?t=452
        if /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*$/ =~ addr
          return true
        end

        false
      end
      # rubocop:enable Layout/LineLength, Style/SpecialGlobalVars
    end
  end
end
