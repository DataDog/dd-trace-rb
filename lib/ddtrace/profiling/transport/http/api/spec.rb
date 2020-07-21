require 'ddtrace/transport/http/api/spec'

module Datadog
  module Profiling
    module Transport
      module HTTP
        module API
          # API specification for profiling
          class Spec < Datadog::Transport::HTTP::API::Spec
            attr_accessor \
              :profiles

            def send_profiling_flush(env, &block)
              raise NoProfilesEndpointDefinedError, self if profiles.nil?
              profiles.call(env, &block)
            end

            def encoder
              profiles.encoder
            end

            # Raised when profiles sent but no profiles endpoint is defined
            class NoProfilesEndpointDefinedError < StandardError
              attr_reader :spec

              def initialize(spec)
                @spec = spec
              end

              def message
                'No profiles endpoint is defined for API specification!'
              end
            end
          end
        end
      end
    end
  end
end
