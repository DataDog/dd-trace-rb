require_relative '../core/configuration'
require_relative 'metadata/ext'
require_relative 'span'

require 'ipaddr'

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
      def self.set_client_ip_tag(span, headers: nil, remote_ip: nil)
        return unless configuration.enabled

        set_client_ip_tag!(span, headers: headers, remote_ip: remote_ip)
      end

      # Forcefully sets the `http.client_ip` tag on the given span.
      #
      # This function ignores the user's `enabled` setting.
      #
      # @param [Span] span The span that's associated with the request.
      # @param [HeaderCollection, #get, nil] headers A collection with the request headers.
      # @param [String, nil] remote_ip The remote IP the request associated with the span is sent to.
      def self.set_client_ip_tag!(span, headers: nil, remote_ip: nil)
        result = raw_ip_from_request(headers, remote_ip)

        if result.raw_ip
          ip = strip_decorations(result.raw_ip)
          return unless valid_ip?(ip)

          span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP, ip)
        elsif result.multiple_ip_headers
          span.set_tag(TAG_MULTIPLE_IP_HEADERS, result.multiple_ip_headers.keys.join(','))
        end
      end

      IpExtractionResult = Struct.new(:raw_ip, :multiple_ip_headers)

      # Returns a result struct that holds the raw client IP associated with the request if it was
      #   retrieved successfully.
      #
      # The client IP is looked up by the following logic:
      # * If the user has configured a header name, return that header's value.
      # * If exactly one of the known IP headers is present, return that header's value.
      # * If none of the known IP headers are present, return the remote IP from the request.
      #
      # If more than one of the known IP headers is present, the result will have a `multiple_ip_headers`
      #   field with the name of the present IP headers.
      #
      # @param [Datadog::Core::HeaderCollection, #get, nil] headers The request headers
      # @param [String] remote_ip The remote IP of the request.
      # @return [IpExtractionResult] A struct that holds the unprocessed IP value,
      #   or `nil` if it wasn't found. Additionally, the `multiple_ip_headers` fields will hold the
      #   name of known IP headers present in the request if more than one of these were found.
      def self.raw_ip_from_request(headers, remote_ip)
        return IpExtractionResult.new(headers && headers.get(configuration.header_name), nil) if configuration.header_name

        headers_present = ip_headers(headers)

        case headers_present.size
        when 0
          IpExtractionResult.new(remote_ip, nil)
        when 1
          IpExtractionResult.new(headers_present.values.first, nil)
        else
          IpExtractionResult.new(nil, headers_present)
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

      # Determines whether the given string is a valid IPv4 or IPv6 address.
      def self.valid_ip?(ip)
        # Client IPs should not have subnet masks even though IPAddr can parse them.
        return false if ip.include?('/')

        begin
          IPAddr.new(ip)

          true
        rescue IPAddr::Error
          false
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
    end
  end
end
