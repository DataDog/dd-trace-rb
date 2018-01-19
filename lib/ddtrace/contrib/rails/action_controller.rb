require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'rails.action_controller' spans.
      module ActionController
        def self.instrument
          # patch Rails core components
          Datadog::RailsActionPatcher.patch_action_controller
        end

        def self.start_processing(payload)
          # trace the execution
          tracer = Datadog.configuration[:rails][:tracer]
          service = Datadog.configuration[:rails][:controller_service]
          type = Datadog::Ext::HTTP::TYPE
          span = tracer.trace('rails.action_controller', service: service, span_type: type)

          # attach the current span to the tracing context
          tracing_context = payload.fetch(:tracing_context)
          tracing_context[:dd_request_span] = span
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.finish_processing(payload)
          # retrieve the tracing context and the latest active span
          tracing_context = payload.fetch(:tracing_context)
          span = tracing_context[:dd_request_span]
          return unless span && !span.finished?

          begin
            # Set the resource name, if it's still the default name
            if span.resource == span.name
              span.resource = "#{payload.fetch(:controller)}##{payload.fetch(:action)}"
            end

            # Set the parent resource if it's a `rack.request` span,
            # but not if its an exception contoller.
            if !span.parent.nil? && span.parent.name == 'rack.request' && !exception_controller?(payload)
              span.parent.resource = span.resource
            end

            span.set_tag('rails.route.action', payload.fetch(:action))
            span.set_tag('rails.route.controller', payload.fetch(:controller))

            if payload[:exception].nil?
              # [christian] in some cases :status is not defined,
              # rather than firing an error, simply acknowledge we don't know it.
              status = payload.fetch(:status, '?').to_s
              span.status = 1 if status.starts_with?('5')
            else
              error = payload[:exception]
              if defined?(::ActionDispatch::ExceptionWrapper)
                status = ::ActionDispatch::ExceptionWrapper.status_code_for_exception(error[0])
                status = status ? status.to_s : '?'
              else
                status = '500'
              end
              span.set_error(error) if status.starts_with?('5')
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
