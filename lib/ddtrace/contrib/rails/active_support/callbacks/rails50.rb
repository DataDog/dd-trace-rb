module Datadog
  module Contrib
    module Rails
      module ActiveSupport
        module Callbacks
          # Callbacks module specifically for Rails 5.0
          module Rails50
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
                user_callback = lambda_with_datadog_tracing(make_lambda(@filter))

                case kind
                when :before
                  ::ActiveSupport::Callbacks::Filters::Before.build(
                    callback_sequence,
                    user_callback,
                    user_conditions,
                    chain_config,
                    @filter
                  )
                when :after
                  ::ActiveSupport::Callbacks::Filters::After.build(
                    callback_sequence,
                    user_callback,
                    user_conditions,
                    chain_config
                  )
                when :around
                  ::ActiveSupport::Callbacks::Filters::Around.build(
                    callback_sequence,
                    user_callback,
                    user_conditions,
                    chain_config
                  )
                end
              end

              # Name - Method being wrapped by callbacks (e.g. process_action)
              # Kind - What kind of callbacked (e.g. before/after)
              # Key -  Method invoked as a callback (e.g. my_before_method)
              def lambda_with_datadog_tracing(original_lambda)
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
