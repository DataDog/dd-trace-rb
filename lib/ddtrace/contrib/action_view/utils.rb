require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module ActionView
      # common utilities for Rails
      module Utils
        module_function

        # in Rails the template name includes the template full path
        # and it's better to avoid storing such information. This method
        # returns the relative path from `views/` or the template name
        # if a `views/` folder is not in the template full path. A wrong
        # usage ensures that this method will not crash the tracing system.
        def normalize_template_name(name)
          return if name.nil?

          base_path = Datadog.configuration[:action_view][:template_base_path]
          sections_view = name.split(base_path)

          if sections_view.length == 1
            name.split('/')[-1]
          else
            sections_view[-1]
          end
        rescue
          return name.to_s
        end
      end
    end
  end
end
