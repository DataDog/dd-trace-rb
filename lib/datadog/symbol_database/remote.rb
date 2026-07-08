# frozen_string_literal: true

require_relative "../di/fatal_exceptions"

module Datadog
  module SymbolDatabase
    # Provides remote configuration integration for symbol database.
    #
    # Responsibilities:
    # - Registers with Core::Remote as a receiver for LIVE_DEBUGGING_SYMBOL_DB product
    # - Processes remote config changes (insert/update/delete)
    # - Calls Component.start_upload when upload_symbols: true
    # - Calls Component.stop_upload when config deleted or upload_symbols: false
    #
    # Flow:
    # 1. Remote config system calls receiver with repository and changes
    # 2. For each change, process_change called
    # 3. parse_config extracts upload_symbols flag
    # 4. enable_upload or disable_upload called on component
    #
    # Created by: Symbol database initialization
    # Accessed by: Core::Remote system when configurations change
    # Requires: Component must exist (accessed via Datadog.send(:components).symbol_database)
    #
    # @api private
    module Remote
      PRODUCT = "LIVE_DEBUGGING_SYMBOL_DB"

      class << self
        # Declare products this receiver handles.
        # @return [Array<String>] Product names
        def products
          [PRODUCT]
        end

        # Declare capabilities for this receiver.
        # @return [Array] Capabilities (none for symbol database)
        def capabilities
          []
        end

        # Create receivers for remote configuration.
        # @return [Array<Receiver>] Array of receivers
        def receivers(_telemetry)
          receiver do |repository, changes|
            telemetry = lookup_telemetry
            component = begin
              Datadog.send(:components, allow_initialization: false)&.symbol_database
            rescue Exception => e # standard:disable Lint/RescueException
              Datadog::DI.reraise_if_fatal(e)
              Datadog.logger.debug { "symdb: failed to look up component in RC receiver: #{e.class}: #{e.message}" }
              telemetry&.report(e, description: "symdb: failed to look up component in RC receiver")
              nil
            end

            if component
              changes.each do |change|
                process_change(component, change, telemetry)
              end
            end
          end
        end

        # Create a single receiver for the product.
        # @param products [Array<String>] Product names to match
        # @return [Array<Receiver>] Receiver array
        def receiver(products = [PRODUCT], &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
        end

        private

        # Look up the telemetry component for error reporting. Returns nil if the
        # component tree isn't built yet (very early boot) or the lookup raises.
        # `allow_initialization: false` avoids triggering component-tree construction
        # from inside an RC receiver callback.
        # @return [Core::Telemetry::Component, nil]
        # @api private
        def lookup_telemetry
          Datadog.send(:components, allow_initialization: false)&.telemetry
        rescue Exception => e # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(e)
          nil
        end

        # Process a single configuration change.
        # @param component [Component] Symbol database component
        # @param change [Change] Configuration change (:insert, :update, :delete)
        # @param telemetry [Core::Telemetry::Component, nil] Telemetry for error reporting
        # @return [void]
        # @api private
        def process_change(component, change, telemetry)
          case change.type
          when :insert
            # @type var change: ::Datadog::Core::Remote::Configuration::Repository::Change::Inserted
            enable_upload(component, change.content)
            change.content.applied
          when :update
            # @type var change: ::Datadog::Core::Remote::Configuration::Repository::Change::Updated
            disable_upload(component)
            enable_upload(component, change.content)
            change.content.applied
          when :delete
            # @type var change: ::Datadog::Core::Remote::Configuration::Repository::Change::Deleted
            disable_upload(component)
            change.previous&.applied
          else
            component.logger.debug { "symdb: unrecognized change type: #{change.type}" }
            # Steep cannot narrow `change.content` from a respond_to? check — it sees
            # the Repository::Change union type where `Deleted` lacks `content`.
            change.content.errored("Unrecognized change type: #{change.type}") if change.respond_to?(:content) # steep:ignore NoMethod
          end
        rescue Exception => e # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(e)
          component.logger.debug { "symdb: error processing remote config change: #{e.class}: #{e.message}" }
          telemetry&.report(e, description: "symdb: error processing remote config change")
          # Rescue runs regardless of which branch raised — Steep cannot narrow the
          # union type from a respond_to? check.
          content_obj = change.respond_to?(:content) ? change.content : change.previous # steep:ignore NoMethod
          content_obj&.errored(e.to_s)
        end

        # Enable upload if config has upload_symbols: true.
        # @param component [Component] Symbol database component
        # @param content [Content] Remote config content
        # @return [void]
        # @api private
        def enable_upload(component, content)
          config = parse_config(content, component.logger)

          unless config
            return
          end

          if config["upload_symbols"]
            component.logger.debug { "symdb: upload enabled via remote config" }
            component.start_upload
          else
            component.logger.debug { "symdb: upload disabled in config" }
          end
        end

        # Disable upload.
        # @param component [Component] Symbol database component
        # @return [void]
        # @api private
        def disable_upload(component)
          component.logger.debug { "symdb: upload disabled via remote config" }
          component.stop_upload
        end

        # Parse and validate remote config content.
        # @param content [Content] Remote config content
        # @param logger [SymbolDatabase::Logger] Logger for invalid-config diagnostics
        # @return [Hash, nil] Parsed config or nil if invalid
        # @api private
        #
        # JSON::ParserError is intentionally NOT rescued here — it propagates to
        # process_change's rescue, which logs and reports to telemetry. Catching
        # it locally would swallow the error from telemetry observability.
        def parse_config(content, logger)
          config = JSON.parse(content.data)

          unless config.is_a?(Hash)
            logger.debug { "symdb: invalid config format: expected Hash, got #{config.class}" }
            return nil
          end

          unless config.key?("upload_symbols")
            logger.debug { "symdb: missing 'upload_symbols' key in config" }
            return nil
          end

          config
        end
      end
    end
  end
end
