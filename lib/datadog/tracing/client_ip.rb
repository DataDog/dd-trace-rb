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

      TAG_MULTIPLE_IP_HEADERS = '_dd.multiple-ip-headers'.freeze

      # Sets the `http.client_ip` tag on the given span.
      #
      # This function respects the user's settings: if they disable the client IP tagging,
      #   or provide a different IP header name.
      #
      # If multiple IP headers are present in the request, this function will instead set
      #   the `_dd.multiple-ip-headers` tag with the names of the present headers,
      #   and **NOT** set the `http.client_ip` tag.
      #
      # @param [Span] span The span that's associated with the request.
      # @param [HeaderCollection, #get, nil] headers A collection with the request headers.
      # @param [String, nil] remote_ip The remote IP the request associated with the span is sent to.
      def self.set_client_ip_tag(span, headers, remote_ip)
        return if configuration.disabled

        begin
          address = raw_ip_from_request(headers, remote_ip)
          if address.nil?
            # `address` can be `nil` if a custom header is configured but not present in the request.
            # In that case, assume misconfiguration and avoid setting the tag.
            return
          end

          ip = strip_decorations(address)

          validate_ip(ip)

          span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, ip)
        rescue InvalidIpError
          # Do nothing, assuming logs will spam here.
        rescue MultipleIpHeadersError => e
          span.set_tag(TAG_MULTIPLE_IP_HEADERS, e.header_names.join(','))
        end
      end

      # Returns the value of an IP-related header or the request's remote IP.
      #
      # The client IP is looked up by the following logic:
      # * If the user has configured a header name, return that header's value.
      # * If exactly one of the known IP headers is present, return that header's value.
      # * If none of the known IP headers are present, return the remote IP from the request.
      #
      # Raises a [MultipleIpHeadersError] if multiple IP-related headers are present.
      #
      # @param [Datadog::Core::HeaderCollection, #get, nil] headers The request headers
      # @param [String] remote_ip The remote IP of the request.
      # @return [String] An unprocessed value retrieved from an
      #   IP header or the remote IP of the request.
      def self.raw_ip_from_request(headers, remote_ip)
        return headers && headers.get(configuration.header_name) if configuration.header_name

        headers_present = ip_headers(headers)

        case headers_present.size
        when 0
          remote_ip
        when 1
          headers_present.values.first
        else
          raise MultipleIpHeadersError, headers_present.keys
        end
      end

      # Removes any port notations or zone specifiers from the IP address without
      #   verifying its validity.
      def self.strip_decorations(address)
        return strip_ipv4_port(address) if likely_ipv4?(address)

        address = strip_ipv6_port(address)

        strip_zone_specifier(address)
      end

      def self.strip_zone_specifier(ipv6)
        ipv6.gsub(/%.*/, '')
      end

      def self.strip_ipv4_port(ip)
        ip.gsub(/:\d+\z/, '')
      end

      def self.strip_ipv6_port(ip)
        if /\[(.*)\](?::\d+)?/ =~ ip
          Regexp.last_match(1)
        else
          ip
        end
      end

      # Returns whether the given value is more likely to be an IPv4 than an IPv6 address.
      #
      # This is done by checking if a dot (`'.'`) character appears before a colon (`':'`) in the value.
      # The rationale is that in valid IPv6 addresses, colons will always preced dots,
      #   and in valid IPv4 addresses dots will always preced colons.
      def self.likely_ipv4?(value)
        dot_index = value.index('.') || value.size
        colon_index = value.index(':') || value.size

        dot_index < colon_index
      end

      def self.validate_ip(ip)
        # IPs with netmasks are invalid.
        raise InvalidIpError if ip.include?('/')

        begin
          IPAddr.new(ip)
        rescue IPAddr::Error
          raise InvalidIpError
        end
      end

      def self.ip_headers(headers)
        return {} unless headers

        DEFAULT_IP_HEADERS_NAMES.each_with_object({}) do |name, result|
          value = headers.get(name)
          result[name] = value unless value.nil?
        end
      end

      def self.configuration
        Datadog.configuration.tracing.client_ip
      end

      class InvalidIpError < RuntimeError
      end

      # An error that represents that multiple IP headers were present in a request,
      # thus a singular IP value could not be determined.
      class MultipleIpHeadersError < RuntimeError
        attr_reader :header_names

        def initialize(header_names)
          super
          @header_names = header_names
        end
      end
    end
  end
end
