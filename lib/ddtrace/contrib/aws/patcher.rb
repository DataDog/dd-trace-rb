require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/aws/ext'

module Datadog
  module Contrib
    module Aws
      # Patcher enables patching of 'aws' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/aws/parsed_context'
          require 'ddtrace/contrib/aws/instrumentation'
          require 'ddtrace/contrib/aws/services'

          add_plugin(Seahorse::Client::Base, *loaded_constants)
        end

        def add_plugin(*targets)
          targets.each { |klass| klass.add_plugin(Instrumentation) }
        end

        def loaded_constants
          # Cross-check services against loaded AWS constants
          # Module#const_get can return a constant from ancestors when there's a miss.
          # If this conincidentally matches another constant, it will attempt to patch
          # the wrong constant, resulting in patch failure.
          available_services = ::Aws.constants & SERVICES.map(&:to_sym)

          available_services.each_with_object([]) do |service, constants|
            next if ::Aws.autoload?(service)
            constants << ::Aws.const_get(service, false).const_get(:Client, false) rescue next
          end
        end

        def get_option(option)
          Datadog.configuration[:aws].get_option(option)
        end
      end
    end
  end
end
