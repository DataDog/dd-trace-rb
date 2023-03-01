# frozen_string_literal: true

module Datadog
  module AppSec
    module Instrumentation
      class Gateway
        # Base class for Gateway Arguments
        class Argument
          def initialize(*); end
        end

        # Gateway User argument
        class User < Argument
          attr_reader :id

          def initialize(id)
            super
            @id = id
          end
        end
      end
    end
  end
end
