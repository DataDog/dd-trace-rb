# frozen_string_literal: true

require_relative "../../../../core/transport/response"
require "uri"
require_relative "native/client"

module Datadog
  module Core
    module Transport
      module HTTP
        module Adapters
          # Adapter that sends requests through the libdatadog native HTTP client
          # Works for TCP/HTTPS and Unix domain sockets, and for multipart forms.
          class Native
            class Error < StandardError
              attr_reader :code

              def initialize(code, message)
                @code = code
                super("native HTTP client error (#{code}): #{message}")
              end
            end

            # The native client requires a base URL even for Unix sockets, where only the
            # request path is used.
            UDS_PLACEHOLDER_BASE_URL = "http://localhost"

            attr_reader :base_url, :uds_path, :timeout

            # @param base_url [String] `http(s)://host[:port]`; a trailing slash is removed
            # @param timeout [Numeric] seconds
            # @param uds_path [String, nil] Unix socket path; when given, `base_url` is ignored
            # @param client [#_native_send] native client, injectable for tests
            def initialize(base_url:, timeout:, uds_path: nil, client: nil)
              @uds_path = uds_path
              @base_url = uds_path ? UDS_PLACEHOLDER_BASE_URL : base_url.to_s.chomp("/")
              @timeout = timeout
              @client = client || Client._native_new(
                base_url: @base_url,
                timeout_ms: Integer(timeout * 1000),
                unix_socket_path: uds_path,
              )
            end

            def self.build(agent_settings)
              if agent_settings.adapter == Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
                new(base_url: nil, timeout: agent_settings.timeout_seconds, uds_path: agent_settings.uds_path)
              else
                new(base_url: agent_settings.url, timeout: agent_settings.timeout_seconds)
              end
            end

            def call(env)
              result = @client._native_send(
                verb: env.verb,
                path: path_from_env(env),
                headers: env.headers.to_a,
                body: multipart?(env) ? nil : env.body,
                multipart: multipart?(env) ? multipart_from_form(env.form) : [],
              )

              case result.first
              when :ok
                _, status, headers, body = result
                Response.new(status, headers, body)
              when :error
                _, code, message = result
                raise Error.new(code, message)
              else
                raise Error.new(:io, "unexpected result from the native client: #{result.inspect}")
              end
            end

            def close
              @client._native_close
            end

            def url
              if uds_path
                "http+unix://#{uds_path}?timeout=#{timeout}"
              else
                "#{base_url}?timeout=#{timeout}"
              end
            end

            private

            def multipart?(env)
              !(env.form.nil? || env.form.empty?)
            end

            def path_from_env(env)
              path = env.path
              case query = env.query
              when Hash
                path + "?" + URI.encode_www_form(query)
              when String
                path + "?" + query
              when nil
                path
              else
                raise ArgumentError, "Invalid type for query: #{query}"
              end
            end

            # Converts a `{name => UploadIO | String}` form into native multipart parts.
            def multipart_from_form(form)
              form.map do |name, value|
                if value.respond_to?(:original_filename) && value.respond_to?(:content_type)
                  io = value.io
                  io.rewind if io.respond_to?(:rewind)
                  {
                    name: name.to_s,
                    data: io.read,
                    filename: value.original_filename,
                    content_type: value.content_type,
                  }
                else
                  {name: name.to_s, data: value.to_s, filename: nil, content_type: nil}
                end
              end
            end

            # A response from the native client that implements the Transport::Response interface.
            class Response
              include Datadog::Core::Transport::Response

              attr_reader :code, :headers, :payload

              # @param code [Integer] HTTP status
              # @param headers [Array<[String, String]>] response headers, in order
              # @param payload [String] response body
              def initialize(code, headers, payload)
                @code = code
                # Names are case-insensitive: keep them lowercased. A repeated header keeps its last value.
                @headers = headers.each_with_object({}) { |(name, value), h| h[name.downcase] = value }
                @payload = payload
              end

              def ok?
                code.between?(200, 299)
              end

              def unsupported?
                code == 415
              end

              def not_found?
                code == 404
              end

              def client_error?
                code.between?(400, 499)
              end

              def server_error?
                code.between?(500, 599)
              end

              def internal_error?
                false
              end
            end
          end
        end
      end
    end
  end
end
