# frozen_string_literal: true

require_relative '../core/remote/dispatcher'

module Datadog
  module OpenFeature
    module Remote
      class << self
        FFE_FLAG_CONFIGURATION_RULES = 1 << 46
        FFE_PRODUCTS = ['FFE_FLAGS'].freeze
        FFE_CAPABILITIES = [FFE_FLAG_CONFIGURATION_RULES].freeze

        def capabilities
          FFE_CAPABILITIES
        end

        def products
          FFE_PRODUCTS
        end

        def receivers(telemetry)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(FFE_PRODUCTS)
          receiver = Core::Remote::Dispatcher::Receiver.new(matcher) do |repository, changes|
            changes.each do |change|
              # no-op
            end
          end

          [receiver]
        end
      end
    end
  end
end
