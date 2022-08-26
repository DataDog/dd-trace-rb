# typed: false

module Datadog
  module Tracing
    module Contrib
      # Class defining hook used to implement method tracing API
      class Hook
        attr_reader \
          :around_block,
          :hook,
          :name,
          :span_options,
          :target

        def self.supported?
          unsupported_reason.nil?
        end

        def self.unsupported_reason
          datadog_instrumentation_gem_unavailable? || datadog_instrumentation_failed_to_load?
        end

        # @param target [String] The class and method to be instrumented.
        # @param name [String] The kind of operation being done, used to name the trace in the Datadog UI.
        # @param span_options [Hash] Optional `Hash` that contains attributes to attach to the span.
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

        # Helper that allows setting span or trace attributes before or after the method call is made. See the
        # [GettingStarted docs](https://docs.datadoghq.com/tracing/trace_collection/dd_libraries/ruby/#method-tracing-api)
        # for details on usage.
        #
        # @param [Proc] Optional block that modifies the span or trace
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

        private_class_method def self.datadog_instrumentation_gem_unavailable?
          if !defined?(::Datadog::Instrumentation) && Gem.loaded_specs['datadog-instrumentation'].nil?
            "Missing datadog-instrumentation dependency; please add `gem 'datadog-instrumentation'` to your Gemfile or " \
            'gems.rb file to use the beta method tracing API.'
          end
        end

        private_class_method def self.datadog_instrumentation_failed_to_load?
          unless datadog_instrumentation_loaded_successfully?
            'There was an error loading the datadog-instrumentation library; see previous warning message for details'
          end
        end

        private_class_method def self.datadog_instrumentation_loaded_successfully?
          return @datadog_instrumentation_loaded if defined?(@datadog_instrumentation_loaded)

          begin
            require 'datadog/instrumentation'
            @datadog_instrumentation_loaded = true
          rescue LoadError => e
            # NOTE: We use Kernel#warn here because this code gets run BEFORE Datadog.logger is actually set up.
            # In the future it'd be nice to shuffle the logger startup to happen first to avoid this special case.
            Datadog.logger.warn(
              '[DDTRACE] Error while loading datadog-instrumentation gem. ' \
              "Cause: '#{e.class.name} #{e.message}' Location: '#{Array(e.backtrace).first}'. " \
              'This can happen when google-protobuf is missing its native components. ' \
              'If the error persists, please contact Datadog support at <https://docs.datadoghq.com/help/>.'
            )
            @datadog_instrumentation_loaded = false
          end
        end
      end
    end
  end
end
