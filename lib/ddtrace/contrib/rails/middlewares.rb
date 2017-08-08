require 'ddtrace/ext/http'

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
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          span.set_error(e) unless span.nil?
          raise e
        end
      end
    end
  end
end
