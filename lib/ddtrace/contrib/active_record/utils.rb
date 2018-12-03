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

        def self.connection_config(connection = nil)
          connection.nil? ? default_connection_config : connection_config_from_connection(connection)
        end

        # Attempt to retrieve the connection config from an object ID.
        # Typical of ActiveSupport::Notifications `sql.active_record`
        def self.connection_config_from_connection(connection)
          if connection.instance_variable_defined?(:@config)
            connection.instance_variable_get(:@config)
          else
            {}
          end
        end

        def self.default_connection_config
          return @default_connection_config if instance_variable_defined?(:@default_connection_config)
          current_connection_name = if ::ActiveRecord::Base.respond_to?(:connection_specification_name)
                                      ::ActiveRecord::Base.connection_specification_name
                                    else
                                      ::ActiveRecord::Base
                                    end

          connection_pool = ::ActiveRecord::Base.connection_handler.retrieve_connection_pool(current_connection_name)
          connection_pool.nil? ? {} : (@default_connection_config = connection_pool.spec.config)
        rescue StandardError
          {}
        end
      end
    end
  end
end
