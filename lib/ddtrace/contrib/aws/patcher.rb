require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/aws/ext'

module Datadog
  module Contrib
    module Aws
      # Patcher enables patching of 'aws' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:aws)
        end

        def patch
          do_once(:aws) do
            begin
              require 'ddtrace/contrib/aws/parsed_context'
              require 'ddtrace/contrib/aws/instrumentation'
              require 'ddtrace/contrib/aws/services'

              add_pin
              add_plugin(Seahorse::Client::Base, *loaded_constants)
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply AWS integration: #{e}")
            end
          end
        end

        def add_pin
          Pin
            .new(
              get_option(:service_name),
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::WEB,
              tracer: get_option(:tracer)
            ).onto(::Aws)
        end

        def add_plugin(*targets)
          targets.each { |klass| klass.add_plugin(Instrumentation) }
        end

        def loaded_constants
          SERVICES.each_with_object([]) do |service, constants|
            next if ::Aws.autoload?(service)
            constants << ::Aws.const_get(service).const_get(:Client) rescue next
          end
        end

        def get_option(option)
          Datadog.configuration[:aws].get_option(option)
        end
      end
    end
  end
end
