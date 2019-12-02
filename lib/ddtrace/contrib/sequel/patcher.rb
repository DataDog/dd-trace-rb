require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/sequel/database'
require 'ddtrace/contrib/sequel/dataset'

module Datadog
  module Contrib
    module Sequel
      # Patcher enables patching of 'sequel' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          patch_sequel_database
          patch_sequel_dataset
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
