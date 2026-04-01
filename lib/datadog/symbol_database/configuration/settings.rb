# frozen_string_literal: true

module Datadog
  module SymbolDatabase
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
                # Enable verbose trace-level logging for symdb operations.
                # Activated by DD_TRACE_DEBUG (same trigger as DI trace logging).
                option :trace_logging do |o|
                  o.type :bool
                  o.default false
                  o.env 'DD_TRACE_DEBUG'
                end

                option :upload_class_methods do |o|
                  o.type :bool
                  o.default false
                end

                # Which RubyVM::InstructionSequence#trace_points event types
                # to include when computing injectable lines on METHOD scopes.
                # Default: [:line, :return]. :call excluded because method
                # entry is handled by method probes, not line probes.
                # Changeable at runtime — takes effect on next extraction.
                option :injectable_line_events do |o|
                  o.default [:line, :return]
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
