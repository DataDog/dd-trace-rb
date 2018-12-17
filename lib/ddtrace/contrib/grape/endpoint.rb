require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'
require 'ddtrace/contrib/rack/ext'

module Datadog
  module Contrib
    module Grape
      # rubocop:disable Metrics/ModuleLength
      # Endpoint module includes a list of subscribers to create
      # traces when a Grape endpoint is hit
      module Endpoint
        KEY_RUN = 'datadog_grape_endpoint_run'.freeze
        KEY_RENDER = 'datadog_grape_endpoint_render'.freeze

        def self.subscribe
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

          # retrieve the tracer from the PIN object
          pin = Datadog::Pin.get_from(::Grape)
          return unless pin && pin.enabled?

          # store the beginning of a trace
          tracer = pin.tracer
          service = pin.service
          type = Datadog::Ext::HTTP::TYPE
          tracer.trace(Ext::SPAN_ENDPOINT_RUN, service: service, span_type: type)

          Thread.current[KEY_RUN] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_run(name, start, finish, id, payload)
          return unless Thread.current[KEY_RUN]
          Thread.current[KEY_RUN] = false

          # retrieve the tracer from the PIN object
          pin = Datadog::Pin.get_from(::Grape)
          return unless pin && pin.enabled?

          tracer = pin.tracer
          span = tracer.active_span
          return unless span

          begin
            # collect endpoint details
            api = payload[:endpoint].options[:for]
            # If the API inherits from Grape::API in version >= 1.2.0
            # then the API will be an instance and the name must be derived from the base.
            # See https://github.com/ruby-grape/grape/issues/1825
            api_view = if defined?(::Grape::API::Instance) && api <= ::Grape::API::Instance
                         api.base.to_s
                       else
                         api.to_s
                       end

            path = payload[:endpoint].options[:path].join('/')
            resource = "#{api_view}##{path}"
            span.resource = resource

            # set the request span resource if it's a `rack.request` span
            request_span = payload[:env][Datadog::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN]
            if !request_span.nil? && request_span.name == Datadog::Contrib::Rack::Ext::SPAN_REQUEST
              request_span.resource = resource
            end

            # catch thrown exceptions
            span.set_error(payload[:exception_object]) unless payload[:exception_object].nil?

            # override the current span with this notification values
            span.set_tag(Ext::TAG_ROUTE_ENDPOINT, api_view) unless api_view.nil?
            span.set_tag(Ext::TAG_ROUTE_PATH, path)
          ensure
            span.start_time = start
            span.finish(finish)
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_start_render(*)
          return if Thread.current[KEY_RENDER]

          # retrieve the tracer from the PIN object
          pin = Datadog::Pin.get_from(::Grape)
          return unless pin && pin.enabled?

          # store the beginning of a trace
          tracer = pin.tracer
          service = pin.service
          type = Datadog::Ext::HTTP::TYPE
          tracer.trace(Ext::SPAN_ENDPOINT_RENDER, service: service, span_type: type)

          Thread.current[KEY_RENDER] = true
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_render(name, start, finish, id, payload)
          return unless Thread.current[KEY_RENDER]
          Thread.current[KEY_RENDER] = false

          # retrieve the tracer from the PIN object
          pin = Datadog::Pin.get_from(::Grape)
          return unless pin && pin.enabled?

          tracer = pin.tracer
          span = tracer.active_span
          return unless span

          # catch thrown exceptions
          begin
            span.set_error(payload[:exception_object]) unless payload[:exception_object].nil?
          ensure
            span.start_time = start
            span.finish(finish)
          end
        rescue StandardError => e
          Datadog::Tracer.log.error(e.message)
        end

        def self.endpoint_run_filters(name, start, finish, id, payload)
          # retrieve the tracer from the PIN object
          pin = Datadog::Pin.get_from(::Grape)
          return unless pin && pin.enabled?

          # safe-guard to prevent submitting empty filters
          zero_length = (finish - start).zero?
          filters = payload[:filters]
          type = payload[:type]
          return if (!filters || filters.empty?) || !type || zero_length

          tracer = pin.tracer
          service = pin.service
          type = Datadog::Ext::HTTP::TYPE
          span = tracer.trace('grape.endpoint_run_filters', service: service, span_type: type)

          begin
            # catch thrown exceptions
            span.set_error(payload[:exception_object]) unless payload[:exception_object].nil?
            span.set_tag(Ext::TAG_FILTER_TYPE, type.to_s)
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
