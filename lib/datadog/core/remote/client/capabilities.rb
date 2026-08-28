# frozen_string_literal: true

require_relative "../../utils/base64_codec"
require_relative "../../../appsec/remote"
require_relative "../../../tracing/remote"
require_relative "../../../di/remote"
require_relative "../../../symbol_database"
require_relative "../../../symbol_database/remote"

module Datadog
  module Core
    module Remote
      class Client
        # Capabilities
        class Capabilities
          def initialize(settings, telemetry)
            @capabilities = []
            @products = []
            @receivers = []
            @telemetry = telemetry
            @mutex = Mutex.new

            register(settings)

            @base64_capabilities = capabilities_to_base64
          end

          def capabilities
            @mutex.synchronize { @capabilities.dup }
          end

          def products
            @mutex.synchronize { @products.dup }
          end

          def receivers
            @mutex.synchronize { @receivers.dup }
          end

          def base64_capabilities
            @mutex.synchronize { @base64_capabilities }
          end

          def register_runtime(capabilities:, products:, receivers:)
            @mutex.synchronize do
              register_capabilities(capabilities)
              register_products(products)
              register_receivers(receivers)
              @base64_capabilities = capabilities_to_base64
            end
            nil
          end

          def add_products(*products)
            @mutex.synchronize { register_products(products) }
            nil
          end

          def remove_products(*products)
            @mutex.synchronize { products.each { |product| @products.delete(product) } }
            nil
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

            if settings.respond_to?(:dynamic_instrumentation) &&
                !Datadog::DI::Remote.explicitly_disabled?(settings) &&
                Datadog::DI.supported_runtime?
              register_capabilities(Datadog::DI::Remote.capabilities)
              register_receivers(Datadog::DI::Remote.receivers(@telemetry))
            end

            # Skip symbol database registration on runtimes that cannot run it
            # (JRuby, Ruby < 2.7): DI supports Ruby 2.6 but Symbol Database does
            # not, so advertising LIVE_DEBUGGING_SYMBOL_DB there would invite
            # symbol-upload configs the component can never serve.
            if settings.respond_to?(:symbol_database) && Datadog::SymbolDatabase.supported_runtime?
              # Symbol database follows DI: when unset it advertises whenever DI
              # advertises (mirror the DI branch above, including the unset/default
              # case that RC may enable). An explicit symbol_database.enabled wins.
              di_enabled = settings.respond_to?(:dynamic_instrumentation) &&
                !Datadog::DI::Remote.explicitly_disabled?(settings)
              if Datadog::SymbolDatabase.resolve_enabled(settings.symbol_database.enabled, di_enabled)
                register_capabilities(Datadog::SymbolDatabase::Remote.capabilities)
                register_receivers(Datadog::SymbolDatabase::Remote.receivers(@telemetry))
                # Register the product at startup only when symbol_database is
                # explicitly set (true here, since resolve_enabled already
                # excluded false). When it follows DI (enabled nil, default or
                # explicit), defer the product so it is advertised only once DI
                # actually starts.
                unless settings.symbol_database.enabled.nil?
                  register_products(Datadog::SymbolDatabase::Remote.products)
                end
              end
            end
          end

          def register_capabilities(capabilities)
            capabilities.each { |capability| @capabilities << capability unless @capabilities.include?(capability) }
          end

          def register_receivers(receivers)
            receivers.each { |receiver| @receivers << receiver unless @receivers.include?(receiver) }
          end

          def register_products(products)
            products.each { |product| @products << product unless @products.include?(product) }
          end

          def capabilities_to_base64
            return "" if @capabilities.empty?

            cap_to_hexs = @capabilities.reduce(:|).to_s(16).tap { |s| s.size.odd? && s.prepend("0") }.scan(/\h\h/)
            binary = cap_to_hexs.each_with_object([]) { |hex, acc| acc << hex }.map { |e| e.to_i(16) }.pack("C*")

            Datadog::Core::Utils::Base64Codec.strict_encode64(binary)
          end
        end
      end
    end
  end
end
