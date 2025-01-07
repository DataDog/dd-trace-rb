# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # common utilities for Rails
      module Rails
        def self.app_name
          if ::Rails::VERSION::MAJOR >= 6
            ::Rails.application.class.module_parent_name.underscore
          else
            ::Rails.application.class.parent_name.underscore
          end
        end

        def self.railtie_supported?
          !!defined?(::Rails::Railtie)
        end
      end
    end
  end
end
