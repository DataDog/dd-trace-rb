# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"
require_relative "../../core/evp"
require_relative "../../core/transport/http/adapters/unix_socket"
require_relative "../../core/transport/ext"
require_relative "../../version"
require_relative "response"

module Datadog
  module OpenFeature
    module Transport
      # Each attempt owns its connection so connection establishment is a provable pre-send boundary.
      class HTTPClient
        MAX_INFO_BYTES = 65_536
        IDENTITY_HEADERS = {
          "DD-EVP-ORIGIN" => "dd-trace-rb",
          "DD-EVP-ORIGIN-VERSION" => Datadog::VERSION::STRING,
        }.freeze

        def initialize(agent_settings:, site:, api_key:)
          @agent_settings = agent_settings
          @prefix = local_prefix
          @direct_host = direct_host(site)
          @api_key = api_key&.dup&.freeze
        end

        def direct?
          key = @api_key
          !!(@direct_host && key && !key.empty? && !key.match?(/[\r\n]/))
        end

        def request(path, timeout:, payload: nil, direct: false)
          return Response.new if timeout <= 0

          connected = false
          Timeout.timeout(timeout) do
            http = connection(direct)
            http.max_retries = 0
            http.open_timeout = http.read_timeout = timeout
            http.write_timeout = timeout if http.respond_to?(:write_timeout=)
            headers = IDENTITY_HEADERS.merge(
              Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST => "1",
              "Content-Type" => "application/json",
              "Accept-Encoding" => "identity",
            )
            if payload
              if direct
                headers["DD-API-KEY"] = @api_key.to_s
              else
                headers[Core::EVP::SUBDOMAIN_HEADER_NAME] = Core::EVP::EVENT_PLATFORM_INTAKE_SUBDOMAIN
              end
            end
            request_path = direct ? path : @prefix + path
            request = payload ? Net::HTTP::Post.new(request_path, headers) : Net::HTTP::Get.new(request_path, headers)
            request.body = payload if payload

            # Exiting from the response block avoids Net::HTTP's implicit, unbounded body drain.
            catch(:evp_response) do
              http.start do |session|
                connected = true
                session.request(request) do |response|
                  info = read_info(response) if !payload && response.code == "200"
                  throw :evp_response, Response.new(code: response.code.to_i, info: info)
                end
              end
            end
          end
        # Network libraries expose version-specific exceptions. Telemetry must not interrupt the worker.
        rescue => error
          pre_send = !connected && (error.is_a?(Errno::ECONNREFUSED) ||
            error.is_a?(Errno::ENOENT) || error.is_a?(SocketError))
          Response.new(pre_send: pre_send)
        end

        private

        def connection(direct)
          if direct
            raise ArgumentError, "Direct EVP is unavailable" unless direct?

            # Use Ruby's standard proxy and no_proxy support; HTTPS tunnels keep the API key off CONNECT.
            http = direct_connection
            http.use_ssl = true
            http
          elsif @agent_settings.uds_path
            Core::Transport::HTTP::Adapters::UnixSocket::HTTP.new(@agent_settings.uds_path, {})
          else
            http = Net::HTTP.new(@agent_settings.hostname, @agent_settings.port, nil)
            http.use_ssl = @agent_settings.ssl
            http
          end
        end

        def direct_connection
          proxy_url = DATADOG_ENV["https_proxy"] || DATADOG_ENV["HTTPS_PROXY"]
          return Net::HTTP.new(@direct_host.to_s, 443) unless proxy_url

          proxy_url = "http://#{proxy_url}" unless proxy_url.include?("://")
          proxy = URI.parse("https://#{@direct_host}").find_proxy(
            "https_proxy" => proxy_url,
            "no_proxy" => DATADOG_ENV["no_proxy"] || DATADOG_ENV["NO_PROXY"],
          )
          return Net::HTTP.new(@direct_host.to_s, 443, nil) unless proxy

          raise ArgumentError, "Unsupported EVP proxy" unless proxy.is_a?(URI::HTTP) && proxy.scheme == "http" && proxy.hostname

          Net::HTTP.new(@direct_host.to_s, 443, proxy.hostname, proxy.port,
            proxy.user && URI::RFC2396_PARSER.unescape(proxy.user.to_s),
            proxy.password && URI::RFC2396_PARSER.unescape(proxy.password.to_s))
        end

        def read_info(response)
          body = +""
          response.read_body do |chunk|
            throw :evp_response, Response.new if body.bytesize + chunk.bytesize > MAX_INFO_BYTES

            body << chunk
          end
          parsed = JSON.parse(body)
          parsed if parsed.is_a?(Hash)
        end

        def direct_host(site)
          normalized = site.to_s.strip.downcase
          normalized = "datadoghq.com" if normalized.empty?
          return unless normalized.ascii_only? && normalized.length <= 231
          return unless normalized.split(".", -1).all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) }

          "event-platform-intake.#{normalized}"
        end

        def local_prefix
          return "" if @agent_settings.uds_path

          raw_url = DATADOG_ENV[Core::Configuration::Ext::Agent::ENV_DEFAULT_URL]
          return "" unless raw_url

          uri = URI.parse(raw_url)
          return "" unless uri.is_a?(URI::HTTP) && uri.hostname == @agent_settings.hostname &&
            uri.port == @agent_settings.port && (uri.scheme == "https") == @agent_settings.ssl

          uri.path.to_s.sub(%r{/+\z}, "").sub(%r{/v(?:0\.[45]|1\.0)/traces\z}, "").freeze
        rescue URI::InvalidURIError
          ""
        end
      end
    end
  end
end
