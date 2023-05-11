# frozen_string_literal: true

require_relative '../../../appsec/remote'

module Datadog
  module Core
    module Remote
      class Client
        # Capbailities
        class Capabilities
          attr_reader :products, :capabilities, :receivers, :base64_capabilities

          def initialize(appsec_enabled)
            @capabilities = []
            @products = []
            @receivers = []

            register(appsec_enabled)

            @base64_capabilities = capabilities_to_base64
          end

          private

          def register(appsec_enabled)
            if appsec_enabled
              register_capabilities(Datadog::AppSec::Remote.capabilities)
              register_products(Datadog::AppSec::Remote.products)
              register_receivers(Datadog::AppSec::Remote.receivers)
            end
          end

          def register_capabilities(capabilities)
            @capabilities.concat(capabilities)
          end

          def register_receivers(receivers)
            @receivers.concat(receivers)
          end

          def register_products(products)
            @products.concat(products)
          end

          def capabilities_to_base64
            return '' if capabilities.empty?

            cap_to_hexs = capabilities.reduce(:|).to_s(16).tap { |s| s.size.odd? && s.prepend('0') }.scan(/\h\h/)
            binary = cap_to_hexs.each_with_object([]) { |hex, acc| acc << hex }.map { |e| e.to_i(16) }.pack('C*')

            Base64.encode64(binary).chomp
          end
        end
      end
    end
  end
end
