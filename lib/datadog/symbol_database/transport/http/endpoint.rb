# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'

module Datadog
  module SymbolDatabase
    module Transport
      module HTTP
        module API
          # Endpoint for symbol database uploads
          # Supports multipart form-data via env.form parameter
          class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
            attr_reader :encoder

            # @param path [String] URL path for the endpoint
            # @param encoder [#encode] Encoder for request data
            def initialize(path, encoder)
              super(:post, path)
              @encoder = encoder
            end

            def call(env, &block)
              # For symbol database, we use multipart form-data
              # The env.form parameter triggers multipart in Net adapter
              # No need to set Content-Type - multipart library handles it

              # Note: env.form is set by the uploader when creating the request
              # It should contain the UploadIO objects for event.json and symbols file

              super
            end
          end
        end
      end
    end
  end
end
