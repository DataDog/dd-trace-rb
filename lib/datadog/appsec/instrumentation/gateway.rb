# typed: ignore

module Datadog
  module AppSec
    # Instrumentation for AppSec
    module Instrumentation
      # Instrumentation gateway implementation
      class Gateway
        # Instrumentation gateway middleware
        class Middleware
          attr_reader :key, :block

          def initialize(key, &block)
            @key = key
            @block = block
          end

          def call(stack, env)
            @block.call(stack, env)
          end
        end

        def initialize
          @middlewares = Hash.new { |h, k| h[k] = [] }
        end

        def push(name, env, &block)
          block ||= -> {}

          middlewares = @middlewares[name]

          return [block.call, nil] if middlewares.empty?

          wrapped = lambda do |_env|
            [block.call, nil]
          end

          # TODO: handle exceptions, except for wrapped
          stack = middlewares.reverse.reduce(wrapped) do |next_, middleware|
            lambda do |env_|
              middleware.call(next_, env_)
            end
          end

          stack.call(env)
        end

        def watch(name, key, &block)
          @middlewares[name] << Middleware.new(key, &block) unless @middlewares[name].any? { |m| m.key == key }
        end
      end

      def self.gateway
        @gateway ||= Gateway.new # TODO: not thread safe
      end
    end
  end
end
