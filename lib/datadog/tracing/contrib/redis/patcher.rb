# typed: false
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/redis/ext'
require 'datadog/tracing/contrib/redis/configuration/resolver'
require 'datadog/tracing/contrib/redis/integration'

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
            require 'datadog/tracing/contrib/redis/tags'
            require 'datadog/tracing/contrib/redis/quantize'
            require 'datadog/tracing/contrib/redis/instrumentation'

            ::Redis::Client.include(Instrumentation)
          end
        end
      end
    end
  end
end
