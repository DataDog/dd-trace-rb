module Datadog
  module Contrib
    module ActiveRecord
      # Common utilities for Rails
      module Utils
        EMPTY_CONFIG = {}.freeze

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

        # In newer Rails versions, the `payload` contains both the `connection` and its `object_id` named `connection_id`.
        #
        # So, if rails is recent we'll have a direct access to the connection.
        # Else, we'll find it thanks to the passed `connection_id`.
        #
        # See this PR for more details: https://github.com/rails/rails/pull/34602
        #
        def self.connection_config(connection = nil, connection_id = nil)
          if connection.nil? && connection_id.nil?
            default_connection_config
          else
            conn =
              connection || ::ActiveRecord::Base
              .connection_handler
              .connection_pool_list
              .flat_map(&:connections)
              .find { |c| c.object_id == connection_id }

            conn.respond_to?(:config) ? conn.config : EMPTY_CONFIG
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
          connection_pool.nil? ? EMPTY_CONFIG : (@default_connection_config = connection_pool.spec.config)
        rescue StandardError
          EMPTY_CONFIG
        end
      end
    end
  end
end
