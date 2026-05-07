# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'

module Datadog
  module SymbolDatabase
    module Transport
      module HTTP
        module API
          # POST endpoint for symbol database uploads. Multipart form-data
          # is triggered by setting `env.form` on the request (handled in
          # `Core::Transport::HTTP::Adapters::Net`); the multipart library
          # sets Content-Type itself.
          class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
            attr_reader :encoder

            # @param path [String] URL path for the endpoint
            # @param encoder [#encode] Encoder for request data
            def initialize(path, encoder)
              super(:post, path)
              @encoder = encoder
            end
          end
        end
      end
    end
  end
end
