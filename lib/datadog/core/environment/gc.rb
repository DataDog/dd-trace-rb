# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      # Retrieves garbage collection statistics
      module GC
        def self.stat
          ::GC.stat
        end

        def self.available?
          !!(defined?(::GC) && ::GC.respond_to?(:stat))
        end
      end
    end
  end
end
