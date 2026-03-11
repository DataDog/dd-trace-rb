# frozen_string_literal: true

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
      class << self
        PRODUCT = 'LIVE_DEBUGGING_SYMBOL_DB'

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
        # @param telemetry [Telemetry, nil] Optional telemetry
        # @return [Array<Receiver>] Array of receivers
        def receivers(telemetry)
          receiver do |repository, changes|
            # Get component from global state
            # Ideally should be injected, but follows DI pattern of accessing via global
            component = begin
              Datadog.send(:components)&.symbol_database
            rescue
              nil
            end

            return unless component

            changes.each do |change|
              process_change(component, change)
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

        # Process a single configuration change.
        # @param component [Component] Symbol database component
        # @param change [Change] Configuration change (:insert, :update, :delete)
        # @return [void]
        # @api private
        def process_change(component, change)
          case change.type
          when :insert
            enable_upload(component, change.content)
            change.content.applied
          when :update
            # Re-enable with new config
            disable_upload(component)
            enable_upload(component, change.content)
            change.content.applied
          when :delete
            disable_upload(component)
            # Delete change has 'previous' not 'content'
            change.previous&.applied
          else
            Datadog.logger.debug("SymDB: Unrecognized change type: #{change.type}")
            # Only call errored() if change has content
            change.content.errored("Unrecognized change type: #{change.type}") if change.respond_to?(:content)
          end
        rescue => e
          Datadog.logger.debug("SymDB: Error processing remote config change: #{e.class}: #{e}")
          # Handle both content and previous
          content_obj = change.respond_to?(:content) ? change.content : change.previous
          content_obj&.errored(e.message)
        end

        # Enable upload if config has upload_symbols: true.
        # @param component [Component] Symbol database component
        # @param content [Content] Remote config content
        # @return [void]
        # @api private
        def enable_upload(component, content)
          config = parse_config(content)

          unless config
            return
          end

          if config['upload_symbols']
            Datadog.logger.debug("SymDB: Upload enabled via remote config")
            component.start_upload
          else
            Datadog.logger.debug("SymDB: Upload disabled in config")
          end
        end

        # Disable upload.
        # @param component [Component] Symbol database component
        # @return [void]
        # @api private
        def disable_upload(component)
          Datadog.logger.debug("SymDB: Upload disabled via remote config")
          component.stop_upload
        end

        # Parse and validate remote config content.
        # @param content [Content] Remote config content
        # @return [Hash, nil] Parsed config or nil if invalid
        # @api private
        def parse_config(content)
          # Parse JSON string to Hash
          # content.data is a JSON string, not a Hash (matches DI pattern: lib/datadog/di/remote.rb:144)
          config = JSON.parse(content.data)

          # Validate it's actually a Hash
          unless config.is_a?(Hash)
            Datadog.logger.debug("SymDB: Invalid config format: expected Hash, got #{config.class}")
            return nil
          end

          unless config.key?('upload_symbols')
            Datadog.logger.debug("SymDB: Missing 'upload_symbols' key in config")
            return nil
          end

          config
        rescue JSON::ParserError => e
          Datadog.logger.debug("SymDB: Invalid config format: #{e.message}")
          nil
        end
      end
    end
  end
end
