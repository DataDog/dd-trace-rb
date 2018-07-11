require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/sequel/database'
require 'ddtrace/contrib/sequel/dataset'

module Datadog
  module Contrib
    module Sequel
      # Patcher enables patching of 'sequel' module.
      # This is used in monkey.rb to manually apply patches
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:sequel)
        end

        def patch
          do_once(:sequel) do
            begin
              patch_sequel_database
              patch_sequel_dataset
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Sequel integration: #{e}")
            end
          end
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
