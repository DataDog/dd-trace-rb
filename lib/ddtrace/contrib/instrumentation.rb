module Datadog
  module Contrib
    # TODO: Add docs
    # placeholder
    module Instrumentation
      # def self.extended(base)
      #  base.extend ClassMethods
      # end

      # module ClassMethods

      def wip_dsl_suggestion
        span_option :service, -> { configuration[:controller_service] }
        configuration_from :action_pack
      end

      def dd_with_configuration
        old_config = config
        yield(dd_instrument)
      ensure
        self.config = old_config
      end

      def enabled?
        configuration[:enabled] == true
      end

      def span_options
        { service: service_name }
      end

      def service_name
        configuration[:service_name]
      end

      def tracer_configuration
        -> { configuration[:tracer] }
      end

      def configuration
        base_configuration.tap do |config|
          return config.options_hash.merge(@options) if @options
        end
      end

      def base_configuration
        raise NotImplementedError, 'Base configuration must be provided'
      end

      def merge_with_configuration!(options)
        @options = options
      end

      # TODO: have an indirect configuartion method to allow for:
      # TODO: @options = Datadog.configuration[:faraday].options_hash.merge(options)
      # def configuration
      #  datadog_configuration
      # end

      def resolve_configuration(config)
        config.is_a?(Proc) ? config.call : config
      end

      # end

      def tracer
        resolve_configuration(tracer_configuration)
      end

      def trace(name, options = {}, &block)
        # if false # TODO: integrate this?
        #  if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
        #    Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
        #  end
        # end

        if block_given?
          tracer.trace(name, **span_options, **options, &block) do |span|
            doit(span)
          end
        else
          tracer.trace(name, **span_options, **options, &block).tap do |span|
            doit(span)
          end
        end
      end

      # Extension for instrumentations using `datadog_pin` ({Datadog::Pin})
      module Pin
        def service_name
          (datadog_pin && datadog_pin.service) || super
        end

        def tracer
          (datadog_pin && datadog_pin.tracer) || super
        end
      end

      module Analytics
        #  if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
        #    Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
        #  end
      end

      module Peer
        def peer_serive_name
          span.service
        end

        def doit(span)
          span.set_tag...
        end
      end
    end
  end
end
