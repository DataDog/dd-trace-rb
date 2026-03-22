# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Remote Configuration integration for symbol database upload.
    # Subscribes to LIVE_DEBUGGING_SYMBOL_DB product.
    #
    # @api private
    module Remote
      class << self
        PRODUCT = 'LIVE_DEBUGGING_SYMBOL_DB'

        def products
          [PRODUCT]
        end

        def capabilities
          []
        end

        def receivers(telemetry)
          receiver do |repository, changes|
            component = SymbolDatabase.component
            next unless component

            changes.each do |change|
              begin
                case change.type
                when :insert, :update
                  content = change.content
                  if content.is_a?(Hash) && content['upload_symbols'] == true
                    component.start_upload
                  end
                when :delete
                  # Config removed — no action needed
                end
              rescue => e
                Datadog.logger.debug { "symbol_database: error processing RC change: #{e.class}: #{e}" }
              end
            end
          end
        end

        def receiver(products = [PRODUCT], &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
        end
      end
    end
  end
end
