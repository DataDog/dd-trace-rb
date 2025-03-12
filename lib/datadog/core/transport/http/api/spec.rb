# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      module HTTP
        module API
          # Specification for an HTTP API
          # Defines behaviors without specific configuration details.
          class Spec
            class EndpointNotDefinedError < StandardError
              attr_reader :spec
              attr_reader :endpoint_name

              def initialize(spec, endpoint_name)
                @spec = spec
                @endpoint_name = endpoint_name

                super(message)
              end

              def message
                "No #{endpoint_name} endpoint is defined for API specification!"
              end
            end

            def initialize
              yield(self) if block_given?
            end
          end
        end
      end
    end
  end
end
