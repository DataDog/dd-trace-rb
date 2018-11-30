module Datadog
  module Contrib
    module ActiveRecord
      # Common utilities for Rails
      module Utils
        def self.adapter_name
          Datadog::Utils::Database.normalize_vendor(connection_config[:adapter])
        end

        def self.database_name
          connection_config[:database]
        end

        def self.adapter_host
          connection_config[:host]
        end

        def self.adapter_port
          connection_config[:port]
        end

        def self.connection_config
          ::ActiveRecord::Base.connection.config
        end
      end
    end
  end
end
