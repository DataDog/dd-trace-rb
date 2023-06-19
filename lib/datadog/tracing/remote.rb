# frozen_string_literal: true

require_relative '../core/remote/dispatcher'

module Datadog
  module Tracing
    # Remote configuration declaration
    module Remote
      class ReadError < StandardError; end

      class << self
        PRODUCT = 'APM_LIBRARY'

        def products
          [PRODUCT]
        end

        def capabilities
          []
        end

        def receivers
          receiver do |repository, _changes|
            config = []

            # DEV: Filter our by product. Given it will be very common
            # DEV: we can filter this out before we receive the data in this method.
            # DEV: Apply this refactor to AppSec as well if implemented.
            repository.contents.each do |content|
              case content.path.product
              when PRODUCT
                config << parse_content(content)
              end
            end

            # TODO: Will there only be one element in the `config` array?
            kw_config = config.first.transform_keys { |key| key.to_sym }
            Tracing::Component.reconfigure(**kw_config)
          end
        end

        def receiver(products = [PRODUCT], &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher) do |repository, changes|
            changes.each do |change|
              Datadog.logger.debug { "remote config change: '#{change.path}'" }
            end
            yield(repository, changes)
          end]
        end

        private

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
