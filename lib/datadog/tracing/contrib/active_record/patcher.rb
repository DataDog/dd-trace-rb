# typed: true

require_relative '../patcher'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Patcher enables patching of 'active_record' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require_relative 'events'
            require_relative 'bullet'

            Events.subscribe!
            Bullet.patch!
          end
        end
      end
    end
  end
end
