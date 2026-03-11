# frozen_string_literal: true

require_relative '../core/transport/request'
require_relative '../core/transport/parcel'

module Datadog
  module SymbolDatabase
    module Transport
      # Transport client wrapper for symbol database uploads
      # Wraps Core::Transport::HTTP::Client with symbol database-specific request handling
      class Client
        attr_reader :http_client

        def initialize(http_client)
          @http_client = http_client
        end

        # Send a symbol database upload request
        # @param form [Hash] Multipart form data with UploadIO objects
        # @return [Core::Transport::Response] Response from agent
        def send_symdb_payload(form)
          # Create request with multipart form
          # The env.form parameter triggers multipart in Core::Transport::HTTP::Adapters::Net
          env = Core::Transport::HTTP::Env.new(
            path: '/symdb/v1/input',
            verb: :post,
            form: form  # This triggers multipart handling in Net adapter!
          )

          http_client.send_request(env)
        end
      end

      # Request wrapper for symbol database payloads
      class Request < Core::Transport::Request
        attr_reader :form

        def initialize(form:)
          @form = form
          super(nil)  # No parcel needed - using form instead
        end
      end
    end
  end
end
