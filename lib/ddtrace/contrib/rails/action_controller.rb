require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'

module Datadog
  module Contrib
    module Rails
      # Code used to create and handle 'rails.action_controller' spans.
      module ActionController
        KEY = 'datadog_actioncontroller'.freeze

        def self.instrument
          # subscribe when the request processing starts
          ::ActiveSupport::Notifications.subscribe('start_processing.action_controller') do |*args|
            start_processing(*args)
          end

          # subscribe when the request processing has been completed
          ::ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
            process_action(*args)
          end
        end

        def self.start_processing(_name, _start, _finish, _id, payload)
          # trace the execution
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          service = ::Rails.configuration.datadog_trace.fetch(:default_controller_service)
          type = Datadog::Ext::HTTP::TYPE
          span = tracer.trace('rails.action_controller', service: service, span_type: type)

          # attach a tracing context to the Request
          tracing_context = {
            dd_request_span: span
          }
          request = payload[:headers].instance_variable_get(:@req)
          request[:tracing_context] = tracing_context
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.process_action(_name, start, finish, _id, payload)
          # retrieve the tracing context and the latest active span
          request = payload[:headers].instance_variable_get(:@req)
          tracing_context = request[:tracing_context]
          span = tracing_context[:dd_request_span]
          return unless span && !span.finished?

          begin
            resource = "#{payload.fetch(:controller)}##{payload.fetch(:action)}"
            span.resource = resource

            # set the parent resource if it's a `rack.request` span
            if !span.parent.nil? && span.parent.name == 'rack.request'
              span.parent.resource = resource
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
            span.start_time = start
            span.finish(finish)
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
