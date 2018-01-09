module Datadog
  module Contrib
    module Rails
      # common utilities for Rails
      module Utils
        # in Rails the template name includes the template full path
        # and it's better to avoid storing such information. This method
        # returns the relative path from `views/` or the template name
        # if a `views/` folder is not in the template full path. A wrong
        # usage ensures that this method will not crash the tracing system.
        def self.normalize_template_name(name)
          return if name.nil?

          base_path = Datadog.configuration[:rails][:template_base_path]
          sections_view = name.split(base_path)

          if sections_view.length == 1
            name.split('/')[-1]
          else
            sections_view[-1]
          end
        rescue
          return name.to_s
        end

        # TODO: Consider moving this out of Rails.
        # Return a canonical name for a type of database
        def self.normalize_vendor(vendor)
          case vendor
          when nil
            'defaultdb'
          when 'sqlite3'
            'sqlite'
          when 'postgresql'
            'postgres'
          else
            vendor
          end
        end

        def self.app_name
          if ::Rails::VERSION::MAJOR >= 4
            ::Rails.application.class.parent_name.underscore
          else
            ::Rails.application.class.to_s.underscore
          end
        end

        def self.adapter_name
          normalize_vendor(connection_config[:adapter])
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
          @connection_config ||= begin
            if defined?(::ActiveRecord::Base.connection_config)
              ::ActiveRecord::Base.connection_config
            else
              ::ActiveRecord::Base.connection_pool.spec.config
            end
          end
        end

        private_class_method :connection_config
      end
    end
  end
end
