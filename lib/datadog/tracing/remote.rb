# frozen_string_literal: true

require_relative '../core/remote/dispatcher'
require_relative 'processor/rule_merger'
require_relative 'processor/rule_loader'

module Datadog
  module Tracing
    # Remote configuration declaration
    module Remote
      class ReadError < StandardError; end
      class NoRulesError < StandardError; end

      class << self
        PRODUCT = 'APM_LIBRARY'

        # DEV: Ugly abstraction
        PRODUCTS = [PRODUCT]

        def products
          remote_features_enabled? ? [ASM_PRODUCT] : []
        end

        # DEV: Ugly abstraction
        # DEV: Reuse
        def receiver(products = PRODUCTS, &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher) do |repository, changes|
            changes.each do |change|
              Datadog.logger.debug { "remote config change: '#{change.path}'" }
            end
            block.call(repository, changes)
          end]
        end

        def receivers
          receiver do |repository, changes|
            config = []

            # DEV: shortcut to retrieve by product, given it will be very common?
            # DEV: maybe filter this out before we receive the data in this method.
            repository.contents.each do |content|
              case content.path.product
              when PRODUCT
                config << parse_content(content)
              end
            end

            Tracing::Component.reconfigure(config)
          end
        end

        private

        # DEV: Reuse
        def parse_content(content)
          data = content.data.read

          content.data.rewind

          raise ReadError, 'EOF reached' if data.nil?

          JSON.parse(data)
        end
      end
    end
  end
end
