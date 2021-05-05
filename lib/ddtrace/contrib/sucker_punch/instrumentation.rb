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
        # rubocop:disable Metrics/AbcSize
        def patch!
          # rubocop:disable Metrics/BlockLength
          ::SuckerPunch::Job::ClassMethods.class_eval do
            def __run_perform_datadog_around
              pin = Datadog::Pin.get_from(::SuckerPunch)
              pin.tracer.provider.context = Datadog::Context.new

              __with_instrumentation(Ext::SPAN_PERFORM) do |span|
                span.resource = "PROCESS #{self}"

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
                end

                # Measure service stats
                Contrib::Analytics.set_measured(span)

                yield
              end
            end
            private :__run_perform_datadog_around

            alias_method :__run_perform_without_datadog, :__run_perform
            if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0')
              def __run_perform(*args)
                __run_perform_datadog_around do
                  __run_perform_without_datadog(*args)
                end
              rescue => e
                ::SuckerPunch.__exception_handler.call(e, self, args)
              end
              ruby2_keywords :__run_perform if respond_to?(:ruby2_keywords, true)
            else
              def __run_perform(*args, **kwargs)
                __run_perform_datadog_around do
                  __run_perform_without_datadog(*args, **kwargs)
                end
              rescue => e
                ::SuckerPunch.__exception_handler.call(e, self, args)
              end
            end

            def perform_async_datadog_around
              __with_instrumentation(Ext::SPAN_PERFORM_ASYNC) do |span|
                span.resource = "ENQUEUE #{self}"

                # Measure service stats
                Contrib::Analytics.set_measured(span)

                yield
              end
            end
            private :perform_async_datadog_around

            alias_method :__perform_async, :perform_async
            if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0')
              def perform_async(*args)
                perform_async_datadog_around do
                  __perform_async(*args)
                end
              end
              ruby2_keywords :perform_async if respond_to?(:ruby2_keywords, true)
            else
              def perform_async(*args, **kwargs)
                perform_async_datadog_around do
                  __perform_async(*args, **kwargs)
                end
              end
            end

            def perform_in_datadog_around(interval)
              __with_instrumentation(Ext::SPAN_PERFORM_IN) do |span|
                span.resource = "ENQUEUE #{self}"
                span.set_tag(Ext::TAG_PERFORM_IN, interval)

                # Measure service stats
                Contrib::Analytics.set_measured(span)

                yield
              end
            end
            private :perform_in_datadog_around

            alias_method :__perform_in, :perform_in
            if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0')
              def perform_in(interval, *args)
                perform_in_datadog_around(interval) do
                  __perform_in(interval, *args)
                end
              end
              ruby2_keywords :perform_in if respond_to?(:ruby2_keywords, true)
            else
              def perform_in(interval, *args, **kwargs)
                perform_in_datadog_around(interval) do
                  __perform_in(interval, *args, **kwargs)
                end
              end
            end

            private

            def datadog_configuration
              Datadog.configuration[:sucker_punch]
            end

            def __with_instrumentation(name)
              pin = Datadog::Pin.get_from(::SuckerPunch)

              pin.tracer.trace(name) do |span|
                span.service = pin.service
                span.span_type = pin.app_type
                span.set_tag(Ext::TAG_QUEUE, to_s)
                yield span
              end
            end
          end
        end
      end
    end
  end
end
