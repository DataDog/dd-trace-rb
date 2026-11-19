# frozen_string_literal: true

require_relative "../patcher"
require_relative "ext"
require_relative "events"

module Datadog
  module Tracing
    module Contrib
      module ActiveModelSerializers
        # Patcher enables patching of 'active_model_serializers' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            Events.subscribe!
          end

          def self.get_option(option)
            Datadog.configuration.tracing[:active_model_serializers].get_option(option)
          end
        end
      end
    end
  end
end
