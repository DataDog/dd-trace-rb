# typed: true
require 'datadog/tracing'
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/rake/ext'
require 'ddtrace/contrib/rake/instrumentation'
require 'ddtrace/contrib/rake/integration'

module Datadog
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
          Tracing.configuration[:rake].get_option(option)
        end
      end
    end
  end
end
