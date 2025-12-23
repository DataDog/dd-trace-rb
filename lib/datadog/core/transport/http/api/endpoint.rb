# frozen_string_literal: true

require 'json'

module Datadog
  module Core
    module Transport
      module HTTP
        module API
          # Endpoint
          class Endpoint
            attr_reader :verb
            attr_reader :path

            # TODO Currently only Traces transport specifies an encoder.
            # Other transports perform encoding "inline" / ad-hoc.
            # They should probably use this encoder field instead.
            attr_reader :encoder

            def initialize(verb, path, encoder: nil)
              @verb = verb
              @path = path
              @encoder = encoder
            end

            def call(env)
              env.verb = verb
              env.path = path
              yield(env)
            end
          end
        end
      end
    end
  end
end
