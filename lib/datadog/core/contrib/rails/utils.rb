# frozen_string_literal: true

module Datadog
  module Core
    module Contrib
      module Rails
        # common utilities for Rails
        module Utils
          def self.app_name
            application_name = if ::Rails::VERSION::MAJOR >= 6
              ::Rails.application.class.module_parent_name
            else
              ::Rails.application.class.parent_name
            end
            application_name&.underscore
          rescue => e
            Datadog.logger.debug("Failed to extract Rails application name: #{e.class}: #{e}")
            nil
          end

          def self.railtie_supported?
            !!defined?(::Rails::Railtie)
          end
        end
      end
    end
  end
end
