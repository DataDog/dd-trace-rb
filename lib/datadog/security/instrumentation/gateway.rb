module Datadog
  module Security
    # Instrumentation for Security
    module Instrumentation
      # Instrumentation gateway implementation
      class Gateway
        def initialize
          @middlewares = Hash.new([])
        end

        def push(name, env, &block)
          block ||= -> {}

          middlewares = @middlewares[name]

          return block.call if middlewares.empty?

          wrapped = lambda do |_env|
            [block.call, nil]
          end

          stack = middlewares.reverse.reduce(wrapped) do |next_, middleware|
            lambda do |env_|
              middleware.call(next_, env_)
            end
          end

          stack.call(env)
        end

        def watch(name, &block)
          @middlewares[name] << block
        end
      end

      def self.gateway
        @gateway ||= Gateway.new
      end
    end
  end
end
