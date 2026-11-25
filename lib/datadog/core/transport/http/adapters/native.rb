# frozen_string_literal: true

require_relative "../../../../core"
require_relative "../../../../core/transport/response"
require_relative "../../../utils/at_fork_monkey_patch"
require "uri"
require_relative "native/in_flight"

module Datadog
  module Core
    module Transport
      module HTTP
        module Adapters
          # Adapter that sends requests through the libdatadog native HTTP client
          # Works for TCP/HTTPS and Unix domain sockets, and for multipart forms.
          #
          # `Native::Client` is implemented in C (`ext/libdatadog_api/http_client.c`) and only exists when the
          # `libdatadog_api` extension was loaded with a libdatadog that includes the HTTP client; see
          # {.supported?}. Its contract:
          #
          # * `Client._native_new(base_url:, timeout_ms:, unix_socket_path:)`: base_url is
          #   `http(s)://host[:port]` without trailing slash, `unix_socket_path` is nil or a path (then `base_url`
          #   is only a placeholder).
          # * `client._native_send(verb:, path:, headers:, body:, multipart:)`, blocking with the GVL released and
          #   cancellable by thread interrupts (`Thread#kill`, `Timeout`).
          #   * `verb`: `:get :post :put :delete :head :patch :options`; the C layer owns that list and raises
          #     `ArgumentError` for any other.
          #   * `path`: starts with `/`, query string included. `headers`: `Array<[String, String]>`.
          #   * `body`: String or nil. `multipart`: `Array<Hash>` of `:name`, `:data`, `:filename`,
          #     `:content_type`, mutually exclusive with `body`.
          #   * Returns `[:ok, status, headers, body]` (every HTTP status, 4xx/5xx included, is `:ok`) or
          #     `[:error, code, message]`, where `code` is a Symbol naming the FFI `HttpClientErrorCode`
          #     (`:timed_out`, `:connection_failed`, `:cancelled`, ...). The C layer owns the set of codes.
          # * `client._native_close`: releases the client; no send may be in flight.
          # * `Client._native_before_fork`, `._native_after_fork_in_parent`, `._native_after_fork_in_child`:
          #   process-wide, for the runtime shared by all the clients; see {.register_fork_hooks}.
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

            # Native calls in flight in the whole process: the runtime shared by all the native clients must not be
            # stopped for a fork while any of them is sending.
            FORK_GUARD = InFlight.new
            private_constant :FORK_GUARD

            REGISTER_FORK_HOOKS_MUTEX = Mutex.new
            private_constant :REGISTER_FORK_HOOKS_MUTEX

            # @return [String, nil] why the native HTTP client cannot be used, or nil if it can.
            def self.unsupported_reason
              if (failure = Datadog::Core::LIBDATADOG_API_FAILURE)
                "the libdatadog_api extension is not available: #{failure}"
              elsif !const_defined?(:Client, false)
                "the libdatadog in use does not include the native HTTP client"
              end
            end

            def self.supported?
              unsupported_reason.nil?
            end

            # Registers, once per process, the hooks that keep a `fork` safe for the runtime shared by all the
            # native clients: before the fork the runtime is paused, once no send is in flight (and new sends wait),
            # and afterwards it is restarted, in the parent and in the child.
            #
            # They are never removed, and do nothing while no client was created.
            def self.register_fork_hooks
              REGISTER_FORK_HOOKS_MUTEX.synchronize do
                return false if @fork_hooks_registered

                @fork_hooks_registered = true
              end

              Core::Utils::AtForkMonkeyPatch.at_fork_blocks(
                before: proc do
                  FORK_GUARD.pause
                  Client._native_before_fork
                rescue => e
                  # The guard stays paused: the parent and child hooks resume it.
                  Datadog.logger.warn { "Native HTTP client before-fork preparation failed: #{e.class}: #{e.message}" }
                end,
                parent: proc do
                  Client._native_after_fork_in_parent
                rescue => e
                  Datadog.logger.warn { "Native HTTP client after-fork reset failed in the parent: #{e.class}: #{e.message}" }
                ensure
                  FORK_GUARD.resume
                end,
                child: proc do
                  Client._native_after_fork_in_child
                rescue => e
                  Datadog.logger.warn { "Native HTTP client after-fork reset failed in the child: #{e.class}: #{e.message}" }
                ensure
                  FORK_GUARD.resume
                end,
              )

              true
            end

            attr_reader :base_url, :uds_path, :timeout

            # @param base_url [String] `http(s)://host[:port]`; a trailing slash is removed
            # @param timeout [Numeric] seconds
            # @param uds_path [String, nil] Unix socket path; when given, `base_url` is ignored
            # @param client [#_native_send] native client, injectable for tests
            def initialize(base_url:, timeout:, uds_path: nil, client: nil)
              @uds_path = uds_path
              @base_url = uds_path ? UDS_PLACEHOLDER_BASE_URL : base_url.to_s.chomp("/")
              @timeout = timeout
              @in_flight = InFlight.new
              @client = client || create_client
            end

            # The timeout of the agent settings is optional: like for `Net::HTTP`, a missing one means the default.
            def self.build(agent_settings)
              if agent_settings.adapter == Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
                timeout = agent_settings.timeout_seconds ||
                  Datadog::Core::Configuration::Ext::Agent::UnixSocket::DEFAULT_TIMEOUT_SECONDS
                new(base_url: nil, timeout: timeout, uds_path: agent_settings.uds_path)
              else
                timeout = agent_settings.timeout_seconds ||
                  Datadog::Core::Configuration::Ext::Agent::HTTP::DEFAULT_TIMEOUT_SECONDS
                new(base_url: agent_settings.url, timeout: timeout)
              end
            end

            def call(env)
              result = send_request(
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

            # Releases the native client, once the sends in flight on this adapter have finished. Later requests
            # raise {Error}. Safe to call more than once.
            def close
              return unless @in_flight.close

              client = @client
              @client = nil
              client&._native_close
              nil
            end

            def url
              if uds_path
                "http+unix://#{uds_path}?timeout=#{timeout}"
              else
                "#{base_url}?timeout=#{timeout}"
              end
            end

            private

            def create_client
              if (reason = Native.unsupported_reason)
                raise "Native HTTP adapter is not supported: #{reason}"
              end

              Native.register_fork_hooks

              Client._native_new(
                base_url: @base_url,
                timeout_ms: Integer(timeout * 1000),
                unix_socket_path: uds_path,
              )
            end

            # The native call is the only thing tracked: it must stay that way, see {InFlight}.
            def send_request(request)
              @in_flight.track do
                FORK_GUARD.track { @client._native_send(request) }
              end
            rescue InFlight::Closed
              raise Error.new(:closed, "the native HTTP adapter is closed")
            end

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
