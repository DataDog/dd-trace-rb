# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Remote configuration integration for symbol database
    module Remote
      PRODUCT = 'LIVE_DEBUGGING_SYMBOL_DB'

      module_function

      def products
        [PRODUCT]
      end

      def capabilities
        []  # No special capabilities needed
      end

      def receivers(telemetry)
        receiver do |repository, changes|
          process_changes(changes)
        end
      end

      def receiver(products = [PRODUCT], &block)
        matcher = Datadog::Core::Remote::Dispatcher::Matcher::Product.new(products)
        [Datadog::Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
      end

      def process_changes(changes)
        component = SymbolDatabase.component
        return unless component

        changes.each do |change|
          process_change(component, change)
        end
      end

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
          change.content.applied
        else
          Datadog.logger.debug("SymDB: Unrecognized change type: #{change.type}")
          change.content.errored("Unrecognized change type: #{change.type}")
        end
      rescue => e
        Datadog.logger.debug("SymDB: Error processing remote config change: #{e.class}: #{e}")
        change.content.errored(e.message)
      end

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

      def disable_upload(component)
        Datadog.logger.debug("SymDB: Upload disabled via remote config")
        component.stop_upload
      end

      def parse_config(content)
        data = content.data

        unless data.is_a?(Hash)
          Datadog.logger.debug("SymDB: Invalid config format, expected Hash, got #{data.class}")
          return nil
        end

        unless data.key?('upload_symbols')
          Datadog.logger.debug("SymDB: Missing 'upload_symbols' key in config")
          return nil
        end

        data
      end
    end
  end
end
