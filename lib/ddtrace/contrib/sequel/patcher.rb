require 'ddtrace/contrib/sequel/database'
require 'ddtrace/contrib/sequel/dataset'

module Datadog
  module Contrib
    module Sequel
      # Patcher enables patching of 'sequel' module.
      # This is used in monkey.rb to manually apply patches
      module Patcher
        include Base

        SERVICE = 'sequel'.freeze
        APP = 'sequel'.freeze

        register_as :sequel, auto_patch: false

        @patched = false

        module_function

        # patched? tells whether patch has been successfully applied
        def patched?
          @patched
        end

        def patch
          if !@patched && defined?(::Sequel)
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
