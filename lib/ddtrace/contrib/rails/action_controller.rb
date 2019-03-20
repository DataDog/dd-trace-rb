require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'
require 'ddtrace/contrib/rack/ext'
require 'ddtrace/contrib/rails/ext'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'rails.action_controller' spans.
      module ActionController
        include Datadog::Patcher

        def self.instrument
          # patch Rails core components
          do_once(:instrument) do
            Datadog::RailsActionPatcher.patch_action_controller
          end
        end

        def self.start_processing(payload)
          # trace the execution
          tracer = Datadog.configuration[:rails][:tracer]
          service = Datadog.configuration[:rails][:controller_service]
          type = Datadog::Ext::HTTP::TYPE
          span = tracer.trace(Ext::SPAN_ACTION_CONTROLLER, service: service, span_type: type)

          # attach the current span to the tracing context
          tracing_context = payload.fetch(:tracing_context)
          tracing_context[:dd_request_span] = span
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.finish_processing(payload)
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
            span.finish()
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.exception_controller?(payload)
          exception_controller_class = Datadog.configuration[:rails][:exception_controller]
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
      end
    end
  end
end
