# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      # Retrieves number of threads from runtime
      module ThreadCount
        def self.value
          Thread.list.count
        end

        def self.available?
          Thread.respond_to?(:list)
        end
      end
    end
  end
end
