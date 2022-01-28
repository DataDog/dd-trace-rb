# typed: false
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/redis/ext'
require 'ddtrace/contrib/redis/configuration/resolver'
require 'ddtrace/contrib/redis/integration'

module Datadog
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
          require 'ddtrace/contrib/redis/tags'
          require 'ddtrace/contrib/redis/quantize'
          require 'ddtrace/contrib/redis/instrumentation'

          ::Redis::Client.include(Instrumentation)
        end
      end
    end
  end
end
