require 'ddtrace/contrib/sequel/database'
require 'ddtrace/contrib/sequel/dataset'

module Datadog
  module Contrib
    module Sequel
      # Patcher enables patching of 'sequel' module.
      # This is used in monkey.rb to manually apply patches
      module Patcher
        include Base

        APP = 'sequel'.freeze

        register_as :sequel, auto_patch: false
        option :service_name
        option :tracer, default: Datadog.tracer

        @patched = false

        module_function

        # patched? tells whether patch has been successfully applied
        def patched?
          @patched
        end

        def patch
          if !@patched && compatible?
            begin
              patch_sequel_database
              patch_sequel_dataset

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Sequel integration: #{e}")
            end
          end

          @patched
        end

        def compatible?
          RUBY_VERSION >= '2.0.0' && defined?(::Sequel)
        end

        def patch_sequel_database
          ::Sequel::Database.send(:include, Database)
        end

        def patch_sequel_dataset
          ::Sequel::Dataset.send(:include, Dataset)
        end
      end
    end
  end
end
