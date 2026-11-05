# frozen_string_literal: true

module Datadog
  module AppSec
    module Instrumentation
      class Gateway
        # Base class for Gateway Arguments
        class Argument; end # rubocop:disable Lint/EmptyClass

        # Gateway User argument
        # NOTE: This class is a subject of elimination and will be removed when
        #       the event system is refactored.
        class User < Argument
          attr_reader :id, :login, :session_id

          def initialize(id = nil, login = nil, session_id = nil)
            super()

            @id = id
            @login = login
            @session_id = session_id
          end
        end

        # This class is used to pass arbitrary data to the event system with an
        # option to tie it to a context.
        #
        # NOTE: This class is a subject of elimination and will be removed when
        #       the event system is refactored.
        class DataContainer < Argument
          attr_reader :data, :context

          def initialize(data, context:)
            super()

            @data = data
            @context = context
          end
        end
      end
    end
  end
end
