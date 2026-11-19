# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      module HTTP
        module Adapters
          class Native
            # Contract of the native (libdatadog `libdd-http-client-ffi`) HTTP client.
            #
            # PHASE 1 MOCK-UP: this class only defines the API surface. In the next phase
            # `_native_new`, `_native_send` and `_native_close` are implemented in C
            # (`ext/libdatadog_api/http_client.c`), blocking with the GVL released and
            # cancellable by thread interrupts. Nothing here talks to the network.
            #
            # @api private
            class Client
              # Error codes that `_native_send` may report, mirroring `HttpClientErrorCode`
              # of the FFI crate.
              ERROR_CODES = [
                :invalid_argument,
                :invalid_config,
                :connection_failed,
                :timed_out,
                :cancelled,
                :io,
                :runtime,
                :panic,
              ].freeze

              # @param config [Hash] with keys
              #   `:base_url` (String, required, `http(s)://host[:port]`, no trailing slash),
              #   `:timeout_ms` (Integer, > 0),
              #   `:unix_socket_path` (String or nil; when set, `base_url` is only a placeholder).
              # @return [Client]
              def self._native_new(config)
                raise NotImplementedError, "native HTTP client is not connected yet"
              end

              # Sends a request, blocking the calling thread (GVL released in the C version).
              #
              # @param request [Hash] with keys
              #   `:verb` (Symbol, one of :get :post :put :delete :head :patch :options),
              #   `:path` (String, starts with `/`, query string included),
              #   `:headers` (Array<[String, String]>),
              #   `:body` (String or nil),
              #   `:multipart` (Array<Hash> of `:name`, `:data`, `:filename`, `:content_type`;
              #     mutually exclusive with `:body`).
              # @return [Array] `[:ok, status, headers, body]` where `headers` is an
              #   `Array<[String, String]>` and `body` a binary String, or
              #   `[:error, code, message]` with `code` one of {ERROR_CODES}.
              #   Every HTTP status, including 4xx/5xx, is reported as `:ok`.
              def _native_send(request)
                raise NotImplementedError, "native HTTP client is not connected yet"
              end

              # Releases the native client. Further sends are not allowed.
              def _native_close
                raise NotImplementedError, "native HTTP client is not connected yet"
              end
            end
          end
        end
      end
    end
  end
end
