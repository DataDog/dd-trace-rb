require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'

module Datadog
  module Contrib
    module Rails
      # TODO[manu]: write docs
      module ActionController
        def self.instrument
          # subscribe when the request processing has been completed
          ::ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
            process_action(*args)
          end
        end

        def self.process_action(_name, _start, _finish, _id, payload)
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          return unless span

          span.resource = "#{payload.fetch(:controller)}##{payload.fetch(:action)}"
          span.set_tag(Datadog::Ext::HTTP::URL, payload.fetch(:path))
          span.set_tag(Datadog::Ext::HTTP::METHOD, payload.fetch(:method))
          span.set_tag('rails.route.action', payload.fetch(:action))
          span.set_tag('rails.route.controller', payload.fetch(:controller))

          if payload[:exception].nil?
            # [christian] in some cases :status is not defined,
            # rather than firing an error, simply acknowledge we don't know it.
            status = payload.fetch(:status, '?').to_s
            span.status = 1 if status.starts_with?('5')
          else
            status = payload.fetch(:status, '500').to_s
            span.status = 1
          end

          span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, status)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
