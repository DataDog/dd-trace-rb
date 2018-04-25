require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/rake/instrumentation'

module Datadog
  module Contrib
    module Rake
      # Patcher for Rake instrumentation
      module Patcher
        include Base

        register_as :rake
        option :service_name, default: 'rake'
        option :tracer, default: Datadog.tracer
        option :enabled, default: true

        module_function

        def patch
          return patched? if patched? || !compatible?

          patch_rake

          # Set service info
          configuration[:tracer].set_service_info(
            configuration[:service_name],
            'rake',
            Ext::AppTypes::WORKER
          )

          @patched = true
        end

        def patched?
          return @patched if defined?(@patched)
          @patched = false
        end

        def patch_rake
          ::Rake::Task.send(:include, Instrumentation)
        end

        def compatible?
          RUBY_VERSION >= '2.0.0' && defined?(::Rake)
        end

        def configuration
          Datadog.configuration[:rake]
        end
      end
    end
  end
end
