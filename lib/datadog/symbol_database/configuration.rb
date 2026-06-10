# frozen_string_literal: true

require_relative '../core/null_logger'

module Datadog
  module SymbolDatabase
    # Configuration for symbol database
    module Configuration
      # Configuration settings for symbol database upload feature.
      #
      # Public environment variable:
      # - DD_SYMBOL_DATABASE_UPLOAD_ENABLED - Feature gate. Independent of
      #   dynamic_instrumentation.enabled — can be set explicitly without DI.
      #   When unset, defaults to true only when DI's setting is enabled AND
      #   DI::Component.environment_supported? returns true; false otherwise.
      #   See the inline comment on the :enabled option for the full rationale.
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
                # Symbol Database and Dynamic Instrumentation are independently
                # configured features: symbol_database.enabled and
                # dynamic_instrumentation.enabled are separate flags, and either
                # can be set explicitly without the other. DI happens to be the
                # canonical consumer of uploaded symbols, but symdb has no hard
                # dependency on a running DI component — a user who wants
                # symbols without DI can set DD_SYMBOL_DATABASE_UPLOAD_ENABLED=true
                # directly.
                #
                # This default is a UX convenience for the common case where
                # symbol_database.enabled has not been set. It tracks DI's full
                # runtime readiness so that an app which sets
                # DD_DYNAMIC_INSTRUMENTATION_ENABLED=true and nothing else gets
                # symbol upload alongside DI without having to opt in twice,
                # and so that environments where DI itself refuses to start
                # (Rails development mode, missing DI C extension, non-MRI
                # engine, ...) don't silently produce ObjectSpace extraction
                # with no DI consumer to use it.
                #
                # The default has two layers:
                # 1. The DI setting itself. symdb's Settings are loaded
                #    unconditionally from core (settings.rb requires this
                #    file). DI's Settings are extended lazily by
                #    lib/datadog/di.rb, which not all load paths reach before
                #    the symdb default fires; the respond_to? guard returns
                #    false in that case.
                # 2. DI::Component.environment_supported? — the same predicate
                #    DI::Component.build runs to decide whether to start.
                #    dynamic_instrumentation.enabled = true is a user intent,
                #    not a runtime fact; consulting environment_supported? at
                #    default-resolution time keeps the default in lockstep
                #    with DI's actual start gate. NULL_LOGGER suppresses the
                #    "di: ..." warnings that environment_supported? would
                #    otherwise emit — DI::Component.build will run with the
                #    operational logger and emit them once at the right layer.
                #
                # Explicit values bypass this default. Setting
                # DD_SYMBOL_DATABASE_UPLOAD_ENABLED=true (or programmatic
                # settings.symbol_database.enabled = true) enables symdb
                # regardless of DI's state; the false counterpart disables
                # symdb even when DI is on.
                o.default do
                  config = Datadog.configuration
                  if config.respond_to?(:dynamic_instrumentation) &&
                      config.dynamic_instrumentation.enabled &&
                      defined?(::Datadog::DI::Component)
                    ::Datadog::DI::Component.environment_supported?(config, ::Datadog::Core::NULL_LOGGER)
                  else
                    false
                  end
                end
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
