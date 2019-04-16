require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/rake/ext'
require 'ddtrace/contrib/rake/instrumentation'

module Datadog
  module Contrib
    module Rake
      # Patcher enables patching of 'rake' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:rake)
        end

        def patch
          do_once(:rake) do
            begin
              # Add instrumentation patch to Rake task
              ::Rake::Task.send(:include, Instrumentation)
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Rake integration: #{e}")
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:rake].get_option(option)
        end
      end
    end
  end
end
