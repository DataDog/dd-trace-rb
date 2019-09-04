require 'ddtrace/ext/http'
require 'ddtrace/contrib/action_pack/utils'

module Datadog
  module Contrib
    # Rails module includes middlewares that are required for Rails to be properly instrumented.
    module Rails
      # This is only here to catch errors, the Rack module does something very similar, however,
      # since it's not in the same place in the stack, when the Rack middleware is called,
      # error is already swallowed and handled by Rails so we miss the call stack, for instance.
      class ExceptionMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          @app.call(env)
        # rubocop:disable Lint/RescueException
        # Here we really want to catch *any* exception, not only StandardError,
        # as we really have no clue of what is in the block,
        # and it is user code which should be executed no matter what.
        # It's not a problem since we re-raise it afterwards so for example a
        # SignalException::Interrupt would still bubble up.
        rescue Exception => e
          tracer = Datadog.configuration[:rails][:tracer]
          span = tracer.active_span
          unless span.nil?
            # Only set error if it's supposed to be flagged as such
            # e.g. we don't want to flag 404s.
            # You can add custom errors via `config.action_dispatch.rescue_responses`
            span.set_error(e) if ActionPack::Utils.exception_is_error?(e)
          end
          raise e
        end
      end
    end
  end
end
