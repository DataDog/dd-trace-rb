module Datadog
  module Tracing
    module Contrib
      module Utils
        # Common database-related utility functions.
        module Database
          VENDOR_DEFAULT = 'defaultdb'.freeze
          VENDOR_POSTGRES = 'postgres'.freeze
          VENDOR_SQLITE = 'sqlite'.freeze

          module_function

          def normalize_vendor(vendor)
            case vendor
            when nil
              VENDOR_DEFAULT
            when 'postgresql'
              VENDOR_POSTGRES
            when 'sqlite3'
              VENDOR_SQLITE
            else
              vendor
            end
          end
        end
      end
    end
  end
end
