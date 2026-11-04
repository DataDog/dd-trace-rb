# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation"

module Datadog
  module Tracing
    module Contrib
      module Mysql2
        # Patcher enables patching of 'mysql2' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            patch_mysql2_client
          end

          def self.patch_mysql2_client
            ::Mysql2::Client.include(Instrumentation)
          end
        end
      end
    end
  end
end
