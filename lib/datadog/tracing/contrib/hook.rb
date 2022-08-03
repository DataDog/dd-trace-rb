# typed: true

require 'datadog/instrumentation'

module Datadog
  module Tracing
    module Contrib
      # Class defining hook used to implement method tracing
      class Hook
        def initialize(name, target, span_options = {})
          @name = name
          @target = target
          @span_options = span_options
        end

        def inject!
          trace_hook = self
          @hook = Datadog::Instrumentation::Hook[@target].add do
            append do |stack, env|
              trace_hook.invoke(stack, env)
            end
          end

          @hook.install
        end

        def around(&block)
          @around = block
          self
        end

        def invoke(stack, env)
          Datadog::Tracing.trace(@name, **@span_options) do |span, trace|
            env_obj = Env.new(env)
            if @around
              @around.call(env_obj, span, trace) do
                stack.call(env)[:return]
              end
            else
              stack.call(env)[:return]
            end
          end
        end

        class Env
          attr_accessor \
            :self,
            :args,
            :kwargs

          def initialize(env)
            @self = env[:self]
            @args = env[:args]
            @kwargs = env[:kwargs]
          end
        end
      end
    end
  end
end
