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

          base_path = ::Rails.configuration.datadog_trace.fetch(:template_base_path, 'views/')
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
          when 'mysql2'
            'mysql'
          else
            vendor
          end
        end
      end
    end
  end
end
