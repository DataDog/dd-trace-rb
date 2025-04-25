# frozen_string_literal: true

require_relative '../ext'

module Datadog
  module ErrorTracking
    module Configuration
      # Settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :error_tracking do
              # Enable automatic reporting of handled errors and set the scope
              # of the errors to report: all | user | third_party
              #
              # @default 'DD_ERROR_TRACKING_HANDLED_ERRORS' environment variable, otherwise `nil`
              # @return [String, nil]
              option :handled_errors do |o|
                o.type :string, nilable: true
                o.default Ext::DEFAULT_HANDLED_ERRORS
                o.env Ext::ENV_HANDLED_ERRORS
                o.setter do |value|
                  next value if Ext::VALID_HANDLED_ERRORS.include?(value)

                  unless value.empty?
                    Datadog.logger.warn(
                      "Invalid handled errors scope: #{value}. " \
                      "Supported values are: #{Ext::VALID_HANDLED_ERRORS.join(' | ')}. " \
                      'Deactivating the feature.'
                    )
                  end

                  Ext::DEFAULT_HANDLED_ERRORS
                end
              end

              # Enable automatic reporting of handled errors and set the module
              # for which handled errors should be reported. List of comma separated modules
              #
              # @default 'DD_ERROR_TRACKING_HANDLED_ERRORS_MODULES' environment variable, otherwise `nil`
              # @return [String, nil]
              option :handled_errors_include do |o|
                o.type :array
                o.default []
                o.env Ext::ENV_HANDLED_ERRORS_INCLUDE
              end
            end
          end
        end
      end
    end
  end
end
