module Datadog
  module Contrib
    module Rails
      module ActiveSupport
        module Callbacks
          # Callbacks module specifically for Rails 5.1
          module Rails51
            def self.included(base)
              base.include(CallbackTracing)
            end

            # Methods to be included into the Callbacks class
            module CallbackTracing
              def self.included(base)
                base.class_eval do
                  alias_method :__callbacks_without_datadog, :__callbacks
                  alias_method :__callbacks, :__callbacks_with_datadog
                end
              end

              def __callbacks_with_datadog
                __callbacks_without_datadog.tap do |callbacks|
                  # TODO: Optimize this... don't loop every time callbacks are retrieved.
                  callbacks.each do |_, chain|
                    unless chain.class < CallbackChain
                      chain.extend(CallbackChain)
                    end
                  end
                end
              end
            end

            # Module for patching the callback chain
            module CallbackChain
              def compile
                # TODO: Optimize this... don't loop every time callbacks are compiled.
                @chain.each do |callback|
                  callback.extend(Callback)
                end

                super
              end
            end

            # Module for wrapping callbacks with tracing
            module Callback
              def apply(callback_sequence)
                user_conditions = conditions_lambdas
                user_callback = ::ActiveSupport::Callbacks::CallTemplate.build(@filter, self)

                case kind
                when :before
                  ::ActiveSupport::Callbacks::Filters::Before.build(
                    callback_sequence,
                    lambda_with_datadog_tracing(user_callback),
                    user_conditions,
                    chain_config,
                    @filter
                  )
                when :after
                  ::ActiveSupport::Callbacks::Filters::After.build(
                    callback_sequence,
                    lambda_with_datadog_tracing(user_callback),
                    user_conditions,
                    chain_config
                  )
                when :around
                  callback_sequence.around(user_callback, user_conditions)
                end
              end

              # Name - Method being wrapped by callbacks (e.g. process_action)
              # Kind - What kind of callbacked (e.g. before/after)
              # Key -  Method invoked as a callback (e.g. my_before_method)
              def lambda_with_datadog_tracing(call_template)
                original_lambda = call_template.make_lambda
                lambda do |target, value, &block|
                  tracer = Datadog.configuration[:rails][:tracer]
                  tracer.trace('active_support.callback') do |span|
                    span.resource = @key.to_s
                    # Assumes its for ActionController... probably not a good idea.
                    span.service = Datadog.configuration[:rails][:controller_service]
                    span.span_type = Ext::HTTP::TYPE
                    span.set_tag('active_support.callback.name', @name.to_s)
                    span.set_tag('active_support.callback.kind', @kind.to_s)
                    span.set_tag('active_support.callback.key', @key.to_s)

                    original_lambda.call(target, value, &block)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
