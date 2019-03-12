require 'ddtrace/ext/app_types'
require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/dalli/quantize'

module Datadog
  module Contrib
    module Dalli
      # Instruments every interaction with the memcached server
      module Instrumentation
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              alias_method :request_without_datadog, :request
              remove_method :request
              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def request(*args, &block)
            request_without_datadog(*args, &block)
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

          def request(op, *args)
            tracer.trace(Datadog::Contrib::Dalli::Ext::SPAN_COMMAND) do |span|
              span.resource = op.to_s.upcase
              span.service = datadog_configuration[:service_name]
              span.span_type = Datadog::Ext::AppTypes::CACHE

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
              end

              span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
              span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)

              super
            end
          end

          private

          def tracer
            datadog_configuration[:tracer]
          end

          def datadog_configuration
            Datadog.configuration[:dalli]
          end
        end
      end
    end
  end
end
