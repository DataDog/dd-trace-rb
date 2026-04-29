# frozen_string_literal: true

require 'date'

require_relative '../../../core/environment/variable_helpers'
require_relative '../../../core/remote/tie/tracing'
require_relative '../../metadata/ext'
require_relative '../http'
require_relative 'ext'
require_relative 'request_queue'
require_relative 'request_tagging'
require_relative 'trace_proxy_middleware'

module Datadog
  module Tracing
    module Contrib
      # Rack module includes middlewares that are required to trace any framework
      # and application built on top of Rack.
      module Rack
        # TraceMiddleware ensures that the Rack Request is properly traced
        # from the beginning to the end. The middleware adds the request span
        # in the Rack environment so that it can be retrieved by the underlying
        # application. If request tags are not set by the app, they will be set using
        # information available at the Rack level.
        class TraceMiddleware
          include RequestTagging

          def initialize(app)
            @app = app
          end

          def call(env)
            # Find out if this is rack within rack
            previous_request_span = env[Ext::RACK_ENV_REQUEST_SPAN]

            return @app.call(env) if previous_request_span

            boot = Datadog::Core::Remote::Tie.boot

            # Extract distributed tracing context before creating any spans,
            # so that all spans will be added to the distributed trace.
            if configuration[:distributed_tracing]
              trace_digest = Contrib::HTTP.extract(env)
              Tracing.continue_trace!(trace_digest) if trace_digest
            end

            TraceProxyMiddleware.call(env, configuration) do
              trace_options = {type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND}
              trace_options[:service] = configuration[:service_name] if configuration[:service_name]

              # start a new request span and attach it to the current Rack environment;
              # we must ensure that the span `resource` is set later
              request_span = Tracing.trace(Ext::SPAN_REQUEST, **trace_options)
              request_span.resource = nil

              # When tracing and distributed tracing are both disabled, `.active_trace` will be `nil`,
              # Return a null object to continue operation
              request_trace = Tracing.active_trace || TraceOperation.new
              env[Ext::RACK_ENV_REQUEST_SPAN] = request_span

              Datadog::Core::Remote::Tie::Tracing.tag(boot, request_span)

              # Copy the original env, before the rest of the stack executes.
              # Values may change; we want values before that happens.
              original_env = env.dup

              # call the rest of the stack
              status, headers, response = @app.call(env)

              [status, headers, response]

            # Here we really want to catch *any* exception, not only StandardError,
            # as we really have no clue of what is in the block,
            # and it is user code which should be executed no matter what.
            # It's not a problem since we re-raise it afterwards so for example a
            # SignalException::Interrupt would still bubble up.
            rescue Exception => e # rubocop:disable Lint/RescueException
              # catch exceptions that may be raised in the middleware chain
              # Note: if a middleware catches an Exception without re raising,
              # the Exception cannot be recorded here.
              request_span&.set_error(e)
              raise e
            ensure
              env[Ext::RACK_ENV_REQUEST_SPAN] = previous_request_span if previous_request_span

              if request_span
                # Rack is a really low level interface and it doesn't provide any
                # advanced functionality like routers. Because of that, we assume that
                # the underlying framework or application has more knowledge about
                # the result for this request; `resource` and `tags` are expected to
                # be set in another level but if they're missing, reasonable defaults
                # are used.
                set_request_tags!(request_trace, request_span, env, status, headers, response, original_env || env)

                # ensure the request_span is finished and the context reset;
                # this assumes that the Rack middleware creates a root span
                request_span.finish
              end
            end
          end
        end
      end
    end
  end
end
