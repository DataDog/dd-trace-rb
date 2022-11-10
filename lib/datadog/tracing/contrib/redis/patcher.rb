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

          module InstancePatch
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            module InstanceMethods
              def initialize(options = {})
                options[:redis_instance] = self

                super(options)
              end
            end
          end

          module ClientPatch
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            module InstanceMethods
              def initialize(options = {})
                @redis_instance = options[:redis_instance]

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

          # patch applies our patch if needed
          def patch
            # do not require these by default, but only when actually patching
            require 'redis'
            require_relative 'tags'
            require_relative 'quantize'
            require_relative 'instrumentation'

            # InstancePatch and ClientPatch allows the client object to access pin on redis instance
            ::Redis.include(InstancePatch)
            ::Redis::Client.include(ClientPatch)

            # TODO: To support redis-rb 5.x, Redis::Client -> RedisClient
            ::Redis::Client.include(Instrumentation)
          end
        end
      end
    end
  end
end
