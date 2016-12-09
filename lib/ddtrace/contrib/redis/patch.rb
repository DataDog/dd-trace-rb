module Datadog
  module Contrib
    module Redis
      # Patch enables patching of 'redis' module.
      module Patch
        @patched = false

        module_function

        def patched?
          @patched
        end

        def patch
          if !@patched && (defined?(::Redis::VERSION) && \
             Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('3.0.0'))
            require 'ddtrace/contrib/redis/core'
            @patched = true
          end
        end
      end
    end
  end
end
