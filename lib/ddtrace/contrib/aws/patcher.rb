module Datadog
  module Contrib
    module Aws
      AGENT = 'aws-sdk-ruby'.freeze
      RESOURCE = 'aws.command'.freeze

      # Responsible for hooking the instrumentation into aws-sdk
      module Patcher
        include Base
        register_as :aws, auto_patch: true
        option :service_name, default: 'aws'

        @patched = false

        class << self
          def patch
            return @patched if patched? || !defined?(Seahorse::Client::Base)

            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/aws/parsed_context'
            require 'ddtrace/contrib/aws/instrumentation'
            require 'ddtrace/contrib/aws/services'

            add_pin
            add_plugin(Seahorse::Client::Base, *loaded_constants)

            @patched = true
          rescue => e
            Datadog::Tracer.log.error("Unable to apply AWS integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def add_pin
            Pin.new(get_option(:service_name), app_type: Ext::AppTypes::WEB).tap do |pin|
              pin.onto(::Aws)
            end
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
        end
      end
    end
  end
end
