require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'

require 'ddtrace/contrib/grape/core_extensions'

module Datadog
  module Contrib
    module Grape
      module Endpoint
        KEY_RUN = 'datadog_grape_endpoint_run'.freeze
        KEY_RENDER = 'datadog_grape_endpoint_render'.freeze

        def self.instrument
          # Grape is instrumented only if it's available
          return unless defined?(::Grape)

          # patch Grape internals
          Datadog::GrapePatcher.patch_grape()

          # subscribe when a Grape endpoint is hit
          ::ActiveSupport::Notifications.subscribe('endpoint_run.grape.start_process') do |*args|
            endpoint_start_process(*args)
          end
          ::ActiveSupport::Notifications.subscribe('endpoint_run.grape') do |*args|
            endpoint_run(*args)
          end
          ::ActiveSupport::Notifications.subscribe('endpoint_render.grape.start_render') do |*args|
            endpoint_start_render(*args)
          end
          ::ActiveSupport::Notifications.subscribe('endpoint_render.grape') do |*args|
            endpoint_render(*args)
          end
          ::ActiveSupport::Notifications.subscribe('endpoint_run_filters.grape') do |*args|
            endpoint_run_filters(*args)
          end
        end

        def self.endpoint_start_process(*)
          return if Thread.current[KEY_RUN]

          # store the beginning of a trace
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          service = ::Rails.configuration.datadog_trace.fetch(:default_grape_service)
          type = Datadog::Ext::HTTP::TYPE
          tracer.trace('grape.endpoint_run', service: service, span_type: type)

          Thread.current[KEY_RUN] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_run(name, start, finish, id, payload)
          return unless Thread.current[KEY_RUN]
          Thread.current[KEY_RUN] = false

          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          return unless span

          # TODO: check if it's really something
          # namespace = ::Grape::Namespace.joined_space(payload[:endpoint].namespace_stackable(:namespace))
          #
          # collect endpoint details
          api_view = payload[:endpoint].options[:for].to_s
          path = payload[:endpoint].options[:path].join('/')
          resource = "#{api_view}##{path}"

          # set the parent resource if it's a `rack.request`
          request_span = payload[:env][:datadog_request_span]
          request_span.resource = resource

          # ovverride the current span with this notification values
          span.resource = resource
          span.start_time = start
          span.set_tag('grape.route.endpoint', api_view)
          span.set_tag('grape.route.path', path)
          span.finish_at(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_start_render(*)
          return if Thread.current[KEY_RENDER]

          # store the beginning of a trace
          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          service = ::Rails.configuration.datadog_trace.fetch(:default_grape_service)
          type = Datadog::Ext::HTTP::TYPE
          tracer.trace('grape.endpoint_render', service: service, span_type: type)

          Thread.current[KEY_RENDER] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_render(name, start, finish, id, payload)
          return unless Thread.current[KEY_RENDER]
          Thread.current[KEY_RENDER] = false

          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.active_span()
          return unless span

          span.start_time = start
          span.finish_at(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_run_filters(name, start, finish, id, payload)
          # safe-guard to prevent submitting empty filters
          zero_length = (finish - start) == 0
          filters = payload[:filters]
          type = payload[:type]
          return if (!filters || filters.empty?) || !type || zero_length

          tracer = ::Rails.configuration.datadog_trace.fetch(:tracer)
          span = tracer.trace('grape.endpoint_run_filters', service: 'grape', span_type: 'http')
          span.start_time = start
          span.set_tag('grape.filter.type', type.to_s)
          span.finish_at(finish)
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end
      end
    end
  end
end
