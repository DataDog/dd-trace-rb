require 'ddtrace/contrib/analytics'

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

          base_path = datadog_configuration[:template_base_path]
          sections_view = name.split(base_path)

          if sections_view.length == 1
            name.split('/')[-1]
          else
            sections_view[-1]
          end
        rescue
          return name.to_s
        end

        def self.app_name
          if ::Rails::VERSION::MAJOR >= 4
            ::Rails.application.class.parent_name.underscore
          else
            ::Rails.application.class.to_s.underscore
          end
        end

        def self.exception_is_error?(exception)
          if defined?(::ActionDispatch::ExceptionWrapper)
            # Gets the equivalent status code for the exception (not all are 5XX)
            # You can add custom errors via `config.action_dispatch.rescue_responses`
            status = ::ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name)
            # Only 5XX exceptions are actually errors (e.g. don't flag 404s)
            status.to_s.starts_with?('5')
          else
            true
          end
        end

        def self.set_analytics_sample_rate(span)
          if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
          end
        end

        class << self
          private

          def datadog_configuration
            Datadog.configuration[:rails]
          end
        end
      end
    end
  end
end
