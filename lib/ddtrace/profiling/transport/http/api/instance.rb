require 'ddtrace/transport/http/api/instance'
require 'ddtrace/profiling/transport/http/api/spec'

module Datadog
  module Profiling
    module Transport
      module HTTP
        module API
          # API instance for profiling
          class Instance < Datadog::Transport::HTTP::API::Instance
            def send_profiling_flush(env)
              raise ProfilesNotSupportedError, spec unless spec.is_a?(Spec)

              spec.send_profiling_flush(env) do |request_env|
                call(request_env)
              end
            end

            # Raised when profiles sent to API that does not support profiles
            class ProfilesNotSupportedError < StandardError
              attr_reader :spec

              def initialize(spec)
                @spec = spec
              end

              def message
                'Profiles not supported for this API!'
              end
            end
          end
        end
      end
    end
  end
end
