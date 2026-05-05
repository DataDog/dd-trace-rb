# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Configuration for symbol database
    module Configuration
      # Configuration settings for symbol database upload feature.
      #
      # Public environment variable:
      # - DD_SYMBOL_DATABASE_UPLOAD_ENABLED (default: true) - Feature gate
      #
      # Extended into: Core::Configuration::Settings (via extend)
      # Accessed as: Datadog.configuration.symbol_database.enabled
      # Used by: Component.build (checks if feature enabled)
      module Settings
        # Hook called when this module is extended into a class.
        # @param base [Class, Module] The class or module being extended
        # @return [void]
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        # Add symbol_database settings block to base class.
        # @param base [Class] Base class
        # @return [void]
        def self.add_settings!(base)
          base.class_eval do
            # steep:ignore:start
            settings :symbol_database do
              option :enabled do |o|
                o.type :bool
                o.env 'DD_SYMBOL_DATABASE_UPLOAD_ENABLED'
                o.default true
              end

              # Settings in the 'internal' group are for internal Datadog
              # use only, and are needed to test symbol database or
              # experiment with features not released to customers.
              settings :internal do
                # Bypass remote config — start extraction immediately.
                # Matches Java's DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD
                # and Python's private force_upload setting.
                option :force_upload do |o|
                  o.type :bool
                  o.env 'DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD'
                  o.default false
                end

                # Enable verbose trace-level logging for symdb operations.
                # Activated by DD_TRACE_DEBUG (same trigger as DI trace logging).
                option :trace_logging do |o|
                  o.type :bool
                  o.default false
                  o.env 'DD_TRACE_DEBUG'
                end
              end
            end
            # steep:ignore:end
          end
        end
      end
    end
  end
end
