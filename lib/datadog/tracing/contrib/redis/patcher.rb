# typed: false

require_relative '../patcher'
require_relative 'ext'
require_relative 'configuration/resolver'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Patcher enables patching of 'redis' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          # patch applies our patch if needed
          def patch
            # do not require these by default, but only when actually patching
            require 'redis'
            require_relative 'tags'
            require_relative 'quantize'
            require_relative 'instrumentation'

            ::Redis::Client.include(Instrumentation)
          end
        end
      end
    end
  end
end
