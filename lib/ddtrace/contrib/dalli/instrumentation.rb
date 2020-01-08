require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/dalli/ext'
require 'ddtrace/contrib/dalli/quantize'

module Datadog
  module Contrib
    module Dalli
      # Instruments every interaction with the memcached server
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include Contrib::Instrumentation

          def my_configuration
            { name: Datadog.configuration[:dalli, "#{hostname}:#{port}"] || Datadog.configuration[:dalli] }
          end

          def request(*args, &block)
            return super unless Datadog.tracer.enabled?

            # Before method call
            span = trace(Dalli::Ext::SPAN_COMMAND, service: service)
            span.resource = op.to_s.upcase
            span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            span.set_tag(Datadog::Ext::HTTP::BASE_URL, args.first)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
            cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
            span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)

            super.tap do |ret|
              # After method call
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, ret)
            end
          rescue Exception => e
            # On method error
            span.set_error(e)
            raise e
          ensure
            span.finish
          end

          dd_instrument.decorate(:request, Dalli::Ext::SPAN_COMMAND) do
            before do |span, args, block|
              span.set_tag(Datadog::Ext::HTTP::BASE_URL, args.first)
            end

            after do |span, args, block, ret|
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, ret.code)
            end

            exception do |span, args, block, e|
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, e.code) if e.is_a?(::RestClient::ExceptionWithResponse)
            end
          end

          dd_instrument.decorate(:request, Dalli::Ext::SPAN_COMMAND) do
            around do |span, args, block|
              span.set_tag(Datadog::Ext::HTTP::BASE_URL, args.first)

              yield.tap do |ret|
                span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, ret.code)
              end
            rescue ::RestClient::ExceptionWithResponse => e
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, e.code)
              raise e
            end
          end

          dd_instrument.decorate(:request, Dalli::Ext::SPAN_COMMAND) do
            before do |span, args, block|
              span.resource = op.to_s.upcase
              span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

              span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
              span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)
            end
          end

          # 👍
          dd_instrument.around(:request, Dalli::Ext::SPAN_COMMAND) do |span, args, block|
            span.set_tag(Datadog::Ext::HTTP::BASE_URL, args.first)

            yield.tap do |ret|
              span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, ret.code)
            end
          rescue ::RestClient::ExceptionWithResponse => e
            span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, e.code)
            raise e
          end

          # 👍
          dd_instrument.before(:request, Dalli::Ext::SPAN_COMMAND) do |span, args, block|
            span.resource = op.to_s.upcase
            span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

            span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
            cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
            span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)
          end

          def request(op, *args)
            dd_instrumenter.with_configuration(my_configuration) do |instrument|
              instrument.trace(Dalli::Ext::SPAN_COMMAND) do |span|
                span.resource = op.to_s.upcase
                span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND

                # Set analytics sample rate
                if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                  Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
                end

                span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
                span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
                cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
                span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)

                super
              end
            end
          end

          # TODO: Possible future improvements
          # dd_instrumenter.trace(method(:request)) do |span|
          #  span.name = Dalli::Ext::SPAN_COMMAND
          #  span.resource = op.to_s.upcase
          #  span.span_type = Datadog::Contrib::Dalli::Ext::SPAN_TYPE_COMMAND
          #
          #  # Set analytics sample rate
          #  if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
          #    Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
          #  end
          #
          #  span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
          #  span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
          #  cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
          #  span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)
          #end

          private

          def base_configuration
            Datadog.configuration[:dalli, "#{hostname}:#{port}"] || Datadog.configuration[:dalli]
          end
        end
      end
    end
  end
end
