# typed: true
require 'datadog/tracing'
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/rake/ext'
require 'datadog/tracing/contrib/rake/instrumentation'
require 'datadog/tracing/contrib/rake/integration'

module Datadog
  module Tracing
    module Contrib
      module Rake
        # Patcher enables patching of 'rake' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Add instrumentation patch to Rake task
            ::Rake::Task.include(Instrumentation)
          end

          def get_option(option)
            Datadog.configuration[:rake].get_option(option)
          end
        end
      end
    end
  end
end
