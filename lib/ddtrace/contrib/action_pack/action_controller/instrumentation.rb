require 'ddtrace/ext/http'

require 'ddtrace/contrib/action_pack/ext'
require 'ddtrace/contrib/action_pack/utils'
require 'ddtrace/contrib/rack/middlewares'
require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module ActionPack
      module ActionController
        # Instrumentation for ActionController components
        module Instrumentation
          module_function

          def start_processing(payload)
            # trace the execution
            tracer = Datadog.configuration[:action_pack][:tracer]
            service = Datadog.configuration[:action_pack][:controller_service]
            type = Datadog::Ext::HTTP::TYPE_INBOUND
            span = tracer.trace(Ext::SPAN_ACTION_CONTROLLER, service: service, span_type: type)

            # attach the current span to the tracing context
            tracing_context = payload.fetch(:tracing_context)
            tracing_context[:dd_request_span] = span
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          def finish_processing(payload)
            # retrieve the tracing context and the latest active span
            tracing_context = payload.fetch(:tracing_context)
            env = payload.fetch(:env)
            span = tracing_context[:dd_request_span]
            return unless span && !span.finished?

            begin
              # Set the resource name, if it's still the default name
              if span.resource == span.name
                span.resource = "#{payload.fetch(:controller)}##{payload.fetch(:action)}"
              end

              # Set the resource name of the Rack request span unless this is an exception controller.
              unless exception_controller?(payload)
                rack_request_span = env[Datadog::Contrib::Rack::TraceMiddleware::RACK_REQUEST_SPAN]
                rack_request_span.resource = span.resource if rack_request_span
              end

              # Set analytics sample rate
              Utils.set_analytics_sample_rate(span)

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              # Associate with runtime metrics
              Datadog.runtime_metrics.associate_with_span(span)

              span.set_tag(Ext::TAG_ROUTE_ACTION, payload.fetch(:action))
              span.set_tag(Ext::TAG_ROUTE_CONTROLLER, payload.fetch(:controller))

              exception = payload[:exception_object]
              if exception.nil?
                # [christian] in some cases :status is not defined,
                # rather than firing an error, simply acknowledge we don't know it.
                status = payload.fetch(:status, '?').to_s
                span.status = 1 if status.starts_with?('5')
              elsif Utils.exception_is_error?(exception)
                span.set_error(exception)
              end
            ensure
              span.finish
            end
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          def exception_controller?(payload)
            exception_controller_class = Datadog.configuration[:action_pack][:exception_controller]
            controller = payload.fetch(:controller)
            headers = payload.fetch(:headers)

            # If no exception controller class has been set,
            # guess whether this is an exception controller from the headers.
            if exception_controller_class.nil?
              !headers[:request_exception].nil?
            # If an exception controller class has been specified,
            # check if the controller is a kind of the exception controller class.
            elsif exception_controller_class.is_a?(Class) || exception_controller_class.is_a?(Module)
              controller <= exception_controller_class
            # Otherwise if the exception controller class is some other value (like false)
            # assume that this controller doesn't handle exceptions.
            else
              false
            end
          end

          # Instrumentation for ActionController::Metal
          module Metal
            def process_action(*args)
              # mutable payload with a tracing context that is used in two different
              # signals; it propagates the request span so that it can be finished
              # no matter what
              payload = {
                controller: self.class,
                action: action_name,
                env: request.env,
                headers: {
                  # The exception this controller was given in the request,
                  # which is typical if the controller is configured to handle exceptions.
                  request_exception: request.headers['action_dispatch.exception']
                },
                tracing_context: {}
              }

              begin
                # process and catch request exceptions
                Instrumentation.start_processing(payload)
                result = super(*args)
                status = datadog_response_status
                payload[:status] = status unless status.nil?
                result
              # rubocop:disable Lint/RescueException
              rescue Exception => e
                payload[:exception] = [e.class.name, e.message]
                payload[:exception_object] = e
                raise e
              end
            # rubocop:enable Lint/RescueException
            ensure
              Instrumentation.finish_processing(payload)
            end

            def datadog_response_status
              case response
              when ::ActionDispatch::Response
                response.status
              when Array
                # Likely a Rack response array: first element is the status.
                status = response.first
                status.class <= Integer ? status : nil
              end
            end
          end
        end
      end
    end
  end
end
