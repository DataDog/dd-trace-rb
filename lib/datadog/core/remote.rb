# frozen_string_literal: true

require_relative 'remote/client'

module Datadog
  module Core
    # Module to interact with core remote component
    module Remote
      class << self
        def active_remote
          remote
        end

        def register_capabilities(capabilities)
          return unless active_remote

          Client.register_capabilities(capabilities)
        end

        def register_receivers(receivers)
          return unless active_remote

          Client.register_receivers(receivers)
        end

        def register_products(products)
          return unless active_remote

          Client.register_products(products)
        end

        private

        def components
          Datadog.send(:components)
        end

        def remote
          components.remote
        end
      end
    end
  end
end
