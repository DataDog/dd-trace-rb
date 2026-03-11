# frozen_string_literal: true

require_relative '../core/transport/request'
require_relative '../core/transport/transport'
require_relative '../core/transport/http/client'
require_relative '../core/transport/http/env'

module Datadog
  module SymbolDatabase
    module Transport
      # Request wrapper for symbol database multipart uploads
      class Request < Core::Transport::Request
        attr_reader :form

        # Initialize request with multipart form data
        # @param form [Hash] Multipart form data with UploadIO objects
        def initialize(form)
          @form = form
          super(nil)  # No parcel - using form data instead
        end
      end

      # HTTP client for symbol database uploads
      # Extends Core::Transport::HTTP::Client to support multipart form-data
      class Client < Core::Transport::HTTP::Client
        # Build environment from request, setting form data for multipart
        # @param request [Request] Symbol database request with form data
        # @return [Core::Transport::HTTP::Env] HTTP environment
        def build_env(request)
          # Create Env with form data to trigger multipart in Net adapter
          # The form parameter triggers multipart handling in Core::Transport::HTTP::Adapters::Net (lines 65-74)
          Core::Transport::HTTP::Env.new(request, form: request.form)
        end
      end

      # Transport wrapper for symbol database
      class Transport < Core::Transport::Transport
        # Custom HTTP client class that supports multipart
        self.http_client_class = Client

        # Send a symbol database upload request
        # @param form [Hash] Multipart form data with UploadIO objects
        # @return [Core::Transport::Response] Response from agent
        def send_symdb_payload(form)
          request = Request.new(form)
          client.send_request(:symdb, request)
        end
      end
    end
  end
end
