module Datadog
  module Core
    module ErrorTracking
      # Used to report handled exceptions
      class Component
        attr_accessor :tracepoint

        def self.build(settings, agent_settings, tracer)
          return unless agent_settings.url

          ErrorTracking::Component.new(
            tracer: tracer,
            enabled: settings.errortracking.enabled,
            instrument_user_code: settings.errortracking.instrument_user_code,
            instrument_third_party: settings.errortracking.instrument_third_party,
            instrument_modules: settings.errortracking.instrument_modules,
          )
        end

        def initialize(tracer:, enabled:, instrument_user_code:, instrument_third_party:, instrument_modules:)
          @tracer = tracer[:tracer]
          if enabled
            should_report_error = proc do |tp|
              file_name = tp.raised_exception.backtrace[0].split(':').first
              !file_name.include?('ddtrace')
            end
          elsif instrument_user_code
            should_report_error = proc do |tp|
              file_name = tp.raised_exception.backtrace[0].split(':').first
              get_gem_name(file_name).nil?
            end
          elsif instrument_third_party
            should_report_error = proc do |tp|
              file_name = tp.raised_exception.backtrace[0].split(':').first
              get_gem_name(file_name).nil? && !file_name.include?('ddtrace')
            end
          end

          traced_event = RUBY_VERSION.to_f >= 3.3 ? :rescue : :raise
          @tracepoint = TracePoint.new(traced_event) do |tp|
            active_span = @tracer.active_span
            traced_exception = tp.raised_exception
            if active_span.nil? == false && should_report_error.call(tp)
              active_span.add_exception_event(
                traced_exception,
                generate_span_event(traced_exception)
              )
            end
          end
          @tracepoint.enable
        end

        def stop
          @tracepoint.disable
        end

        def get_gem_name(file_name)
          return false unless file_name.include?('gems')

          gem_name = file_name&.rpartition('gems/')&.last&.split('-')&.first
          Gem::Specification.find_by_name(gem_name)
        end

        def generate_span_event(exception)
          formatted_exception = Core::Error.build_from(exception)
          Tracing::SpanEvent.new(
            'error',
            attributes: {
              type: formatted_exception.type,
              message: formatted_exception.message,
              stacktrace: formatted_exception.backtrace
            }
          )
        end
      end
    end
  end
end
