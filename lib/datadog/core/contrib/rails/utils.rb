# frozen_string_literal: true

module Datadog
  module Core
    module Contrib
      module Rails
        # common utilities for Rails
        module Utils
          def self.app_name
            namespace_method = (::Rails::VERSION::MAJOR >= 6) ? :module_parent_name : :parent_name
            application_name = ::Rails.application.class.public_send(namespace_method)
            application_name&.underscore
          rescue
            # Adds a failsafe during app boot, teardown, or test stubs where the application is not initialized and this check gets performed
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
