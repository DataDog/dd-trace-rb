# frozen_string_literal: true

require_relative "../patcher"
require_relative "database"
require_relative "dataset"

module Datadog
  module Tracing
    module Contrib
      module Sequel
        # Patcher enables patching of 'sequel' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            patch_sequel_database
            patch_sequel_dataset
          end

          def self.patch_sequel_database
            ::Sequel::Database.include(Database)
          end

          def self.patch_sequel_dataset
            ::Sequel::Dataset.include(Dataset)
          end
        end
      end
    end
  end
end
