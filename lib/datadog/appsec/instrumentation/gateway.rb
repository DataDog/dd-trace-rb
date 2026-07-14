# frozen_string_literal: true

require_relative 'gateway/middleware'

module Datadog
  module AppSec
    # Instrumentation for AppSec
    module Instrumentation
      # Instrumentation gateway implementation
      class Gateway
        def initialize
          @middlewares = Hash.new { |h, k| h[k] = [] }
        end

        def push(name, env, &block)
          block ||= -> {}
          middlewares_for_name = @middlewares[name]

          return [block.call, nil] if middlewares_for_name.empty?

          wrapped = lambda do |_env|
            [block.call, nil]
          end

          # TODO: handle exceptions, except for wrapped
          stack = middlewares_for_name.reverse.reduce(wrapped) do |next_, middleware|
            lambda do |env_|
              middleware.call(next_, env_)
            end
          end

          stack.call(env)
        end

        def watch(name, &block)
          @middlewares[name] << Middleware.new(&block)
        end
      end

      # NOTE: This left as-is and will be depricated soon.
      def self.gateway
        @gateway ||= Gateway.new # TODO: not thread safe
      end
    end
  end
end
