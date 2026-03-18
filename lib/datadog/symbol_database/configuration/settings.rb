# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    module Configuration
      # Configuration settings for symbol database upload feature.
      #
      # Provides 3 environment variables:
      # - DD_SYMBOL_DATABASE_UPLOAD_ENABLED (default: true) - Feature gate
      # - DD_SYMBOL_DATABASE_FORCE_UPLOAD (default: false) - Bypass remote config
      # - DD_SYMBOL_DATABASE_INCLUDES (default: []) - Filter modules to upload
      #
      # Extended into: Core::Configuration::Settings (via extend)
      # Accessed as: Datadog.configuration.symbol_database.enabled
      # Used by: Component.build (checks if feature enabled)
      module Settings
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

              option :force_upload do |o|
                o.type :bool
                o.env 'DD_SYMBOL_DATABASE_FORCE_UPLOAD'
                o.default false
              end

              option :includes do |o|
                o.type :array
                o.env 'DD_SYMBOL_DATABASE_INCLUDES'
                o.env_parser do |value|
                  value.to_s.split(',').map(&:strip).reject(&:empty?)
                end
                o.default []
              end

              # Settings in the 'internal' group are for internal Datadog
              # use only, and are needed to test symbol database or
              # experiment with features not released to customers.
              settings :internal do
                # Controls whether class methods (def self.foo) are included
                # in symbol database uploads.
                #
                # Class methods are NOT uploaded by default because Ruby DI
                # currently does not support instrumenting class methods —
                # only instance methods can be probed. Including class methods
                # would present completions in the UI that cannot be acted on.
                #
                # When DI gains singleton class instrumentation support, this
                # should be switched to default true and moved to a public setting.
                #
                # See: docs/class_methods_di_design.md for full analysis.
                option :upload_class_methods do |o|
                  o.type :bool
                  o.default false
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
