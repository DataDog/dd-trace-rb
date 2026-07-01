# frozen_string_literal: true

require_relative '../../utils/base64_codec'
require_relative '../../../appsec/remote'
require_relative '../../../tracing/remote'
require_relative '../../../di/remote'
require_relative '../../../symbol_database'
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

            # Tracing must register before DI: on a combined RC dispatch,
            # the APM_TRACING handler must run first to call
            # Datadog::DI::Remote.handle_rc_enablement and start the
            # component before the DI receiver processes LIVE_DEBUGGING
            # changes against `component.started?`. Reversing the order
            # silently drops the probe — the remote client only
            # redispatches on content hash changes.
            register_capabilities(Datadog::Tracing::Remote.capabilities)
            register_products(Datadog::Tracing::Remote.products)
            register_receivers(Datadog::Tracing::Remote.receivers(@telemetry))

            # Skip DI registration entirely when DI is explicitly disabled
            # (DD_DYNAMIC_INSTRUMENTATION_ENABLED=false): no component will be
            # built, so advertising bit 38 or the LIVE_DEBUGGING product would
            # invite an enable signal the tracer must refuse. When the env var
            # is unset (default), DI is registered so RC can enable it.
            if settings.respond_to?(:dynamic_instrumentation) &&
                !Datadog::DI::Remote.explicitly_disabled?(settings)
              register_capabilities(Datadog::DI::Remote.capabilities)
              register_products(Datadog::DI::Remote.products)
              register_receivers(Datadog::DI::Remote.receivers(@telemetry))
            end

            # Only advertise on runtimes where SymbolDatabase::Component can build
            # (MRI 2.7+). DI supports Ruby 2.6, but Symbol Database does not, so
            # without this guard the product would be advertised on 2.6 while no
            # component exists to service the upload config.
            if settings.respond_to?(:symbol_database) && Datadog::SymbolDatabase.supported?
              # Symbol database follows DI: when unset it advertises whenever DI
              # advertises (mirror the DI branch above, including the unset/default
              # case that RC may enable). An explicit symbol_database.enabled wins.
              di_enabled = settings.respond_to?(:dynamic_instrumentation) &&
                !Datadog::DI::Remote.explicitly_disabled?(settings)
              if Datadog::SymbolDatabase.resolve_enabled(settings.symbol_database.enabled, di_enabled)
                register_capabilities(Datadog::SymbolDatabase::Remote.capabilities)
                register_products(Datadog::SymbolDatabase::Remote.products)
                register_receivers(Datadog::SymbolDatabase::Remote.receivers(@telemetry))
              end
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
