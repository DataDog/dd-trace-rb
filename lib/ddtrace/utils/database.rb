module Datadog
  module Utils
    # Common database-related utility functions.
    module Database
      module_function

      def normalize_vendor(vendor)
        case vendor
        when nil
          'defaultdb'
        when 'postgresql'
          'postgres'
        when 'sqlite3'
          'sqlite'
        else
          vendor
        end
      end
    end
  end
end
