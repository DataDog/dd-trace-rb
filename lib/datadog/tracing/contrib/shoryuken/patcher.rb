# frozen_string_literal: true

require_relative "tracer"

module Datadog
  module Tracing
    module Contrib
      module Shoryuken
        # Patcher enables patching of 'shoryuken' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            ::Shoryuken.server_middleware do |chain|
              chain.add Shoryuken::Tracer
            end
          end
        end
      end
    end
  end
end
