require_relative '../../../../tracing'
require_relative '../../../metadata/ext'

require_relative '../ext'
require_relative '../utils'
require_relative '../../rack/middlewares'
require_relative '../../analytics'

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        module ActionController
          # Instrumentation for ActionController components
          module Instrumentation
            module_function

            def start_processing(payload)
              return unless Tracing.enabled?

              # trace the execution
              service = Datadog.configuration.tracing[:action_pack][:service_name]
              type = Tracing::Metadata::Ext::HTTP::TYPE_INBOUND
              span = Tracing.trace(
                Ext::SPAN_ACTION_CONTROLLER,
                service: service,
                span_type: type,
                resource: "#{payload.fetch(:controller)}##{payload.fetch(:action)}",
              )
              trace = Tracing.active_trace

              # attach the current span to the tracing context
              tracing_context = payload.fetch(:tracing_context)
              tracing_context[:dd_request_trace] = trace
              tracing_context[:dd_request_span] = span

              # We want the route to show up as the trace's resource
              trace.resource = span.resource

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_CONTROLLER)
            rescue StandardError => e
              Datadog.logger.error(e.message)
            end

            def finish_processing(payload)
              return unless Tracing.enabled?

              # retrieve the tracing context and the latest active span
              tracing_context = payload.fetch(:tracing_context)
              trace = tracing_context[:dd_request_trace]
              span = tracing_context[:dd_request_span]
              return unless span && !span.finished?

              begin
                # We repeat this in both start and at finish because the resource may have changed during the request
                trace.resource = span.resource

                # Set analytics sample rate
                Utils.set_analytics_sample_rate(span)

                # Measure service stats
                Contrib::Analytics.set_measured(span)

                span.set_tag(Ext::TAG_ROUTE_ACTION, payload.fetch(:action))
                span.set_tag(Ext::TAG_ROUTE_CONTROLLER, payload.fetch(:controller))

                exception = payload[:exception_object]
                if exception.nil?
                  # [christian] in some cases :status is not defined,
                  # rather than firing an error, simply acknowledge we don't know it.
                  status = payload.fetch(:status, '?').to_s
                  span.status = 1 if status.start_with?('5')
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
              exception_controller_class = Datadog.configuration.tracing[:action_pack][:exception_controller]
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
                  payload[:exception_controller?] = Instrumentation.exception_controller?(payload)

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
end
