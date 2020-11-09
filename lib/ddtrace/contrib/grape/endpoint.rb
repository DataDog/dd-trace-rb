require 'set'
require 'ddtrace/ext/http'
require 'ddtrace/ext/errors'
require 'ddtrace/contrib/analytics'
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

        class << self
          def subscribe
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

          def endpoint_start_process(*)
            return if Thread.current[KEY_RUN]
            return unless enabled?

            # Store the beginning of a trace
            tracer.trace(
              Ext::SPAN_ENDPOINT_RUN,
              service: service_name,
              span_type: Datadog::Ext::HTTP::TYPE_INBOUND
            )

            Thread.current[KEY_RUN] = true
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          def endpoint_run(name, start, finish, id, payload)
            return unless Thread.current[KEY_RUN]
            Thread.current[KEY_RUN] = false

            return unless enabled?

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

              # Set analytics sample rate
              if analytics_enabled?
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate)
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              # catch thrown exceptions

              if exception_is_error?(payload[:exception_object])
                span.set_error(payload[:exception_object])
              end

              # override the current span with this notification values
              span.set_tag(Ext::TAG_ROUTE_ENDPOINT, api_view) unless api_view.nil?
              span.set_tag(Ext::TAG_ROUTE_PATH, path)
            ensure
              span.start(start)
              span.finish(finish)
            end
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          def endpoint_start_render(*)
            return if Thread.current[KEY_RENDER]
            return unless enabled?

            # Store the beginning of a trace
            tracer.trace(
              Ext::SPAN_ENDPOINT_RENDER,
              service: service_name,
              span_type: Datadog::Ext::HTTP::TEMPLATE
            )

            Thread.current[KEY_RENDER] = true
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          def endpoint_render(name, start, finish, id, payload)
            return unless Thread.current[KEY_RENDER]
            Thread.current[KEY_RENDER] = false

            return unless enabled?

            span = tracer.active_span
            return unless span

            # catch thrown exceptions
            begin
              # Measure service stats
              Contrib::Analytics.set_measured(span)

              if exception_is_error?(payload[:exception_object])
                span.set_error(payload[:exception_object])
              end
            ensure
              span.start(start)
              span.finish(finish)
            end
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          def endpoint_run_filters(name, start, finish, id, payload)
            return unless enabled?

            # safe-guard to prevent submitting empty filters
            zero_length = (finish - start).zero?
            filters = payload[:filters]
            type = payload[:type]
            return if (!filters || filters.empty?) || !type || zero_length

            span = tracer.trace(
              Ext::SPAN_ENDPOINT_RUN_FILTERS,
              service: service_name,
              span_type: Datadog::Ext::HTTP::TYPE_INBOUND,
              start_time: start
            )

            begin
              # Set analytics sample rate
              if analytics_enabled?
                Contrib::Analytics.set_sample_rate(span, analytics_sample_rate)
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              # catch thrown exceptions
              if exception_is_error?(payload[:exception_object])
                span.set_error(payload[:exception_object])
              end

              span.set_tag(Ext::TAG_FILTER_TYPE, type.to_s)
            ensure
              span.start(start)
              span.finish(finish)
            end
          rescue StandardError => e
            Datadog.logger.error(e.message)
          end

          private

          def tracer
            datadog_configuration[:tracer]
          end

          def service_name
            datadog_configuration[:service_name]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end

          def error_responses
            return datadog_configuration[:error_responses] if datadog_configuration[:error_responses].kind_of?(String)
            datadog_configuration[:error_responses].join(',') 
          end

          def handle_statuses

            if datadog_configuration[:error_responses].kind_of?(String)
              datadog_configuration[:error_responses].gsub(/\s+/, '').split(',').select do |code|
                if !code.to_s.match(/^\d{3}(?:-\d{3})?(?:,\d{3}(?:-\d{3})?)*$/)
                  Datadog.logger.debug("Invalid config provided: #{code}. Must be formatted like '400-403,405,410-499'.")
                  next
                else
                  true
                end
              end
            else
              Datadog.logger.debug('No valid config was provided for :error_responses - falling back to default.')
              ['500-599'] # Rather than returning an empty array, we need to fallback to default config.
            end
          end

          def set_range
            set = Set.new
            handle_statuses.each do |statuses|
              status = statuses.to_s.split('-')
              if status.length == 1
                set.add(Integer(status[0]))
              elsif status.length == 2
                min, max = status.minmax
                Array(min..max).each do |i|
                  set.add(Integer(i))
                end
              end
            end
            set
          end

          def exception_is_error?(exception)
            status = nil
            return false unless exception
            if exception.respond_to?('status') && set_range.include?(exception.status)
              status = exception.status
            else
              return true
            end
            !status.nil?
          end

          def enabled?
            datadog_configuration[:enabled] == true
          end

          def datadog_configuration
            Datadog.configuration[:grape]
          end
        end
      end
    end
  end
end
