# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module Redis
      # Patcher enables patching of 'redis' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          if !@patched && (defined?(::Redis::VERSION) && \
                           Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('3.0.0'))
            begin
              require 'ddtrace/contrib/redis/core'
              ::Redis.prepend Datadog::Contrib::Redis::TracedRedis
              @patched = true
            rescue StandardError => e
              Datadog::Tracer.error("Unable to apply Redis integration: #{e}")
            end
          end
          @patched
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
