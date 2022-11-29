# typed: ignore

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

          # Patch for redis instance
          module InstancePatch
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance method patch for redis instance
            module InstanceMethods
              # `options` could be frozen
              def initialize(options = {})
                super(options.merge(redis_instance: self))
              end
            end
          end

          # Patch for redis client
          module ClientPatch
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance method patch for redis client
            module InstanceMethods
              def initialize(options = {})
                @redis_instance = options.delete(:redis_instance)

                super(options)
              end

              private

              attr_reader :redis_instance
            end
          end

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Redis 5+ extracts RedisClient to its own gem and provide instrumentation interface
            if target_version >= Gem::Version.new('5.0.0')
              require_relative 'trace_middleware'

              ::RedisClient.register(TraceMiddleware)
            else
              require_relative 'instrumentation'

              ::Redis.include(InstancePatch)
              ::Redis::Client.include(ClientPatch)
              ::Redis::Client.include(Instrumentation)
            end
          end
        end
      end
    end
  end
end
