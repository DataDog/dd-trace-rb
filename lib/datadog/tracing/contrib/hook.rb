# typed: ignore

require 'datadog/instrumentation'

module Datadog
  module Tracing
    module Contrib
      # Class defining hook used to implement method tracing
      class Hook
        attr_reader \
          :around_block,
          :hook,
          :name,
          :span_options,
          :target

        def initialize(target, name, span_options = {})
          @target = target
          @name = name
          @span_options = span_options
        end

        def inject!
          trace_hook = self
          @hook = Datadog::Instrumentation::Hook[target].add do
            append do |stack, env|
              trace_hook.invoke(stack, env)
            end
          end

          hook.install
        end

        def around(&block)
          @around_block = block
          self
        end

        def invoke(stack, env)
          Datadog::Tracing.trace(name, **span_options) do |span, trace|
            if around_block
              env_obj = Env.new(env)
              around_block.call(env_obj, span, trace) do
                stack.call(env)[:return]
              end
            else
              stack.call(env)[:return]
            end
          end
        end

        def disable!
          hook.disable
        end

        def enable!
          hook.enable
        end

        def disabled?
          hook.disabled?
        end

        # Class defining the Env object that can be used to extract information passed to the method to be traced
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
