# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      module HTTP
        module API
          # An API configured with adapter and routes
          class Instance
            attr_reader \
              :adapter,
              :headers,
              :endpoint

            def initialize(endpoint, adapter, options = {})
              @endpoint = endpoint
              @adapter = adapter
              @headers = options.fetch(:headers, {})
            end

            def encoder
              endpoint.encoder
            end

            def call(env)
              env.headers.merge!(headers) unless headers.empty?

              adapter.call(env)
            end
          end
        end
      end
    end
  end
end
