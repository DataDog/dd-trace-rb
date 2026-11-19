# frozen_string_literal: true

require_relative "../patcher"
require_relative "events"

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Patcher enables patching of 'active_record' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            Events.subscribe!
          end
        end
      end
    end
  end
end
