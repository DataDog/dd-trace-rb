module Datadog
  module Contrib
    module Rack
      # A module that injects tracing into the middleware stack itself.
      #
      # It's rather complicated due to the limited introspective capabilities of Rack
      # middlewares, as well as the requirement that middleware spans not be nested.
      # That is, instead of this:
      #
      #   [AAAAAAAAAAAAAAAAAAAAA]
      #     [BBBBBBBBBBBBBBBBBB]
      #        [CCCCCCCC]
      #
      # We want this:
      #
      #   [A][BB][CCCCCCC][BBBB][A]
      #
      # Otherwise we get very deep nesting.
      #
      # The way we go about this is the following:
      #
      # 1) Our middleware, when initialized, travels down the middleware stack from
      #    where it's been inserted, prepending the MiddlewareTracing module to each
      #    middleware class.
      # 2) This module overwrites `call`, allowing us to hook into the point where
      #    e.g. middleware A "hands off" the request to middleware B.
      # 3) When a request is processed, an instrumented middleware will first check
      #    in the Rack environment to see if there's already an open middleware span.
      #    If there is, we call its `finish` method.
      # 4) Then a new span is opened before calling `super` to let the actual middleware
      #    gets to do its thing.
      # 5) This is repeated all the way down the stack, until we reach Rails' routing
      #    system.
      # 6) When the response goes back up the middleware chain (in reverse order),
      #    we want to trace the "after" part of each middleware, the part that
      #    processes the response. So if there was a middleware span "above" our
      #    middleware (the one stored in the Rack env) we "re-open" it by creating
      #    a new span with the same name and resource, and store *that* in the Rack
      #    env. Of course, if the middleware *below* us had already done that for
      #    our middleware, we finish that span first.
      #
      # It's all a bit complicated, but it works!
      module MiddlewareTracing
        SPAN_NAME = 'middleware.call'.freeze
        ENV_KEY = 'ddtrace_middleware_trace'.freeze

        def call(env)
          env['RESPONSE_MIDDLEWARE'] = self.class.to_s

          current_middleware_trace = env[ENV_KEY]
          is_first_middleware = !current_middleware_trace
          is_last_middleware = !defined?(@app)

          # If a previous middleware has started a span, finish it here in order to avoid
          # nesting.
          current_middleware_trace.finish unless is_first_middleware

          if is_last_middleware
            # There are no more middlewares after this one.
            response = super(env)
          else
            trace = Datadog.tracer.trace(SPAN_NAME)
            trace.resource = "#{self.class}#call"

            # Pass the trace to the next middleware.
            env[ENV_KEY] = trace

            response = super(env)

            # The next middleware will set a new span here for the "after" step. Finish
            # that as well. If there's no more middleware, we'll just finish our own trace.
            env[ENV_KEY].finish
          end

          # If the previous middleware set a span, create a matching "after" span that
          # includes the time spent after we return to it.
          unless is_first_middleware
            remainder_trace = Datadog.tracer.trace(SPAN_NAME)
            remainder_trace.parent = current_middleware_trace.parent
            remainder_trace.resource = current_middleware_trace.resource

            env[ENV_KEY] = remainder_trace
          end

          response
        end
      end
    end
  end
end
