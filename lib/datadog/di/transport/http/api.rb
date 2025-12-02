# frozen_string_literal: true

require_relative '../../../core/encoding'
require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/api/map'
require_relative 'diagnostics'
require_relative 'input'

module Datadog
  module DI
    module Transport
      module HTTP
        # Namespace for API components
        module API
          # Default API versions
          DIAGNOSTICS = '/debugger/v1/diagnostics'
          INPUT = '/debugger/v2/input'
          LEGACY_INPUT = 'legacy:/debugger/v1/diagnostics'

          module_function

          def defaults
            Datadog::Core::Transport::HTTP::API::Map[
              DIAGNOSTICS => Diagnostics::API::Endpoint.new(
                '/debugger/v1/diagnostics',
                Core::Encoding::JSONEncoder,
              ),
              INPUT => Input::API::Endpoint.new(
                '/debugger/v2/input',
                Core::Encoding::JSONEncoder,
              ),
              LEGACY_INPUT => Input::API::Endpoint.new(
                # TODO is this really supposed to be diagnostics?
                #'/debugger/v1/diagnostics',
                '/debugger/v1/input',
                Core::Encoding::JSONEncoder,
              ),
            # This fallbacks definition seems to be doing nothing,
            # the fallbacks that are used are actually specified in the DI
            # Transport::HTTP module. # standard:disable Layout/CommentIndentation
            ].with_fallbacks(INPUT => LEGACY_INPUT)
          end
        end
      end
    end
  end
end
