# frozen_string_literal: true

require_relative '../core/transport/request'
require_relative '../core/transport/transport'
require_relative '../core/transport/http/client'
require_relative '../core/transport/http/env'

module Datadog
  module SymbolDatabase
    module Transport
      # Transport classes for the symbols upload endpoint.
      # Mirrors the per-purpose split used by DI (`DI::Transport::Input::*`).
      module Symbols
        # Request wrapper carrying the multipart form for a symbols upload.
        class Request < Core::Transport::Request
          attr_reader :form

          # @param form [Hash] Multipart form data with UploadIO objects
          def initialize(form)
            @form = form
            # Multipart upload — no parcel; the Net adapter reads form data
            # off the env directly.
            super(nil)
          end
        end

        # HTTP client for symbol database uploads.
        # Extends Core::Transport::HTTP::Client to set `env.form`, which the
        # Net adapter (lib/datadog/core/transport/http/adapters/net.rb) detects
        # and dispatches as multipart/form-data.
        class Client < Core::Transport::HTTP::Client
          # @param request [Request] Symbols upload request
          # @return [Core::Transport::HTTP::Env] Env with form data set
          def build_env(request)
            Core::Transport::HTTP::Env.new(request, form: request.form)
          end
        end

        # Transport for the symbols upload endpoint.
        class Transport < Core::Transport::Transport
          self.http_client_class = Client

          # Send a symbols upload to the agent.
          # @param form [Hash] Multipart form data with UploadIO objects
          # @return [Core::Transport::Response] Response from agent
          def send_symbols(form)
            request = Request.new(form)
            client.send_request(:symbols, request)
          end
        end
      end
    end
  end
end
