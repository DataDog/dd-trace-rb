require 'sucker_punch'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/sucker_punch/ext'

module Datadog
  module Contrib
    module SuckerPunch
      # Defines instrumentation patches for the `sucker_punch` gem
      module Instrumentation
        module_function

        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/BlockLength
        def patch!
          ::SuckerPunch::Job::ClassMethods.class.include(Contrib::Instrumentation)
          ::SuckerPunch::Job::ClassMethods.class_eval do
            def service_name
              (@pin && @pin.service) || super
            end

            def tracer
              (@pin && @pin.tracer) || super
            end

            alias_method :__run_perform_without_datadog, :__run_perform
            def __run_perform(*args)
              @pin = Datadog::Pin.get_from(::SuckerPunch)
              tracer.provider.context = Datadog::Context.new

              __with_instrumentation(Ext::SPAN_PERFORM) do |span|
                span.resource = "PROCESS #{self}"
                # Set analytics sample rate
                if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
                end
                __run_perform_without_datadog(*args)
              end
            rescue => e
              ::SuckerPunch.__exception_handler.call(e, self, args)
            end

            alias_method :__perform_async, :perform_async
            def perform_async(*args)
              __with_instrumentation(Ext::SPAN_PERFORM_ASYNC) do |span|
                span.resource = "ENQUEUE #{self}"
                __perform_async(*args)
              end
            end

            alias_method :__perform_in, :perform_in
            def perform_in(interval, *args)
              __with_instrumentation(Ext::SPAN_PERFORM_IN) do |span|
                span.resource = "ENQUEUE #{self}"
                span.set_tag(Ext::TAG_PERFORM_IN, interval)
                __perform_in(interval, *args)
              end
            end

            private

            def base_configuration
              Datadog.configuration[:sucker_punch]
            end

            def __with_instrumentation(name)
              @pin = Datadog::Pin.get_from(::SuckerPunch)

              trace(name) do |span|
                span.span_type = @pin.app_type
                span.set_tag(Ext::TAG_QUEUE, to_s)
                yield span
              end
            ensure
              @pin = nil
            end
          end
        end
      end
    end
  end
end
