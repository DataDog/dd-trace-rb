# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      module ThreadCount
        module_function

        def value
          Thread.list.count
        end

        def available?
          Thread.respond_to?(:list)
        end
      end
    end
  end
end
