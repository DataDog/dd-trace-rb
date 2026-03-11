# frozen_string_literal: true

require 'json'

module Datadog
  module SymbolDatabase
    # Integrates symbol database with Datadog remote configuration system.
    #
    # Subscribes to LIVE_DEBUGGING_SYMBOL_DB product and responds to configuration changes.
    # When backend sends upload_symbols: true, triggers Component.start_upload.
    #
    # Pattern: Follows DI::Remote exactly (product matcher + receiver callback)
    # Registered in: Core::Remote::Client::Capabilities (during tracer initialization)
    # Calls: SymbolDatabase.component.start_upload/stop_upload on config changes
    # Handles: :insert (enable), :update (re-enable), :delete (disable)
    #
    # @api private
    module Remote
      PRODUCT = 'LIVE_DEBUGGING_SYMBOL_DB'

      module_function

      # Return list of remote config products to subscribe to.
      # @return [Array<String>] Product names
      def products
        [PRODUCT]
      end

      # Return capabilities for remote config.
      # @return [Array] Empty array (no special capabilities needed)
      def capabilities
        []  # No special capabilities needed
      end

      # Create remote config receivers.
      # @param telemetry [Telemetry] Telemetry instance
      # @return [Array<Receiver>] Array with receiver callback
      def receivers(telemetry)
        receiver do |repository, changes|
          process_changes(changes)
        end
      end

      # Create receiver with product matcher.
      # @param products [Array<String>] Products to match
      # @yield [repository, changes] Callback when changes match
      # @return [Array<Receiver>] Receiver array
      # @api private
      def receiver(products = [PRODUCT], &block)
        matcher = Datadog::Core::Remote::Dispatcher::Matcher::Product.new(products)
        [Datadog::Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
      end

      # Process all remote config changes.
      # @param changes [Array<Change>] Configuration changes
      # @return [void]
      # @api private
      def process_changes(changes)
        # Access component via components tree instead of global variable
        component = Datadog.send(:components)&.symbol_database
        return unless component

        changes.each do |change|
          process_change(component, change)
        end
      end

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
          change.previous.applied
        else
          Datadog.logger.debug("SymDB: Unrecognized change type: #{change.type}")
          # Get content reference based on change type
          content = change.respond_to?(:content) ? change.content : change.previous
          content&.errored("Unrecognized change type: #{change.type}")
        end
      rescue => e
        Datadog.logger.debug("SymDB: Error processing remote config change: #{e.class}: #{e}")
        # Get content reference based on change type for error reporting
        content = change.respond_to?(:content) ? change.content : change.previous
        content&.errored(e.message)
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
        # content.data is a JSON string, parse it first
        data = JSON.parse(content.data)

        unless data.is_a?(Hash)
          Datadog.logger.debug("SymDB: Invalid config format, expected Hash, got #{data.class}")
          return nil
        end

        unless data.key?('upload_symbols')
          Datadog.logger.debug("SymDB: Missing 'upload_symbols' key in config")
          return nil
        end

        data
      rescue JSON::ParserError => e
        Datadog.logger.debug("SymDB: Failed to parse config JSON: #{e.class}: #{e}")
        nil
      end
    end
  end
end
