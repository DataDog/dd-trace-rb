# frozen_string_literal: true

require_relative '../../utils/base64_codec'
require_relative '../../../appsec/remote'
require_relative '../../../tracing/remote'
require_relative '../../../di/remote'
require_relative '../../../symbol_database/remote'
require_relative '../../../open_feature/remote'

module Datadog
  module Core
    module Remote
      class Client
        # Capabilities
        class Capabilities
          attr_reader :products, :capabilities, :receivers, :base64_capabilities

          def initialize(settings, telemetry)
            @capabilities = []
            @products = []
            @receivers = []
            @telemetry = telemetry

            register(settings)

            @base64_capabilities = capabilities_to_base64
          end

          private

          def register(settings)
            if settings.respond_to?(:appsec) && settings.appsec.enabled
              register_capabilities(Datadog::AppSec::Remote.capabilities)
              register_products(Datadog::AppSec::Remote.products)
              register_receivers(Datadog::AppSec::Remote.receivers(@telemetry))
            end

            # Tracing must register before DI so the APM_TRACING receiver
            # runs first on a combined RC dispatch. The Tracing receiver
            # invokes Datadog::DI::Remote.handle_rc_enablement, which calls
            # component.start! on enable. The DI receiver then processes
            # LIVE_DEBUGGING changes against a started component within the
            # same dispatch pass. Reversing the order would silently drop
            # the probe: the DI receiver runs first, sees component.started?
            # is false, drops the change; the remote client only redispatches
            # on content hash changes, so a subsequent poll with the same
            # probe content would never deliver it again.
            register_capabilities(Datadog::Tracing::Remote.capabilities)
            register_products(Datadog::Tracing::Remote.products)
            register_receivers(Datadog::Tracing::Remote.receivers(@telemetry))

            if settings.respond_to?(:dynamic_instrumentation)
              register_capabilities(Datadog::DI::Remote.capabilities)
              register_products(Datadog::DI::Remote.products)
              register_receivers(Datadog::DI::Remote.receivers(@telemetry))
            end

            if settings.respond_to?(:symbol_database) && settings.symbol_database.enabled
              register_capabilities(Datadog::SymbolDatabase::Remote.capabilities)
              register_products(Datadog::SymbolDatabase::Remote.products)
              register_receivers(Datadog::SymbolDatabase::Remote.receivers(@telemetry))
            end

            if settings.respond_to?(:open_feature) && settings.open_feature.enabled
              register_capabilities(Datadog::OpenFeature::Remote.capabilities)
              register_products(Datadog::OpenFeature::Remote.products)
              register_receivers(Datadog::OpenFeature::Remote.receivers(@telemetry))
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

            Datadog::Core::Utils::Base64Codec.strict_encode64(binary)
          end
        end
      end
    end
  end
end
