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
          attr_reader :capabilities, :receivers, :base64_capabilities

          def initialize(settings, telemetry)
            @capabilities = []
            @products = []
            @products_mutex = Mutex.new
            @receivers = []
            @telemetry = telemetry

            register(settings)

            @base64_capabilities = capabilities_to_base64
          end

          # The RC request re-reads this on every poll (Client#payload). DI implicit
          # enablement adds/removes the LIVE_DEBUGGING(/_SYMBOL_DB) product here when
          # the component starts/stops, so a candidate-but-not-enabled tracer
          # advertises the capability bit but subscribes to no DI product. Guarded by
          # a mutex because the writer runs on the RC worker thread (RC enable) or the
          # main thread (boot / reconfigure) while the reader runs on the RC worker
          # thread at payload build. Returns a snapshot so callers never see the
          # array mutate mid-iteration.
          def products
            @products_mutex.synchronize { @products.dup }
          end

          def add_products(products)
            @products_mutex.synchronize do
              products.each { |product| @products << product unless @products.include?(product) }
            end
          end

          def remove_products(products)
            @products_mutex.synchronize { products.each { |product| @products.delete(product) } }
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

            # Register the DI capability (bit 38) and receiver unless DI is
            # explicitly disabled (DD_DYNAMIC_INSTRUMENTATION_ENABLED=false) or the
            # runtime cannot run DI (JRuby, Ruby 2.5). Bit 38 is the implicit-
            # enablement candidacy signal, carried in the capabilities field.
            #
            # The LIVE_DEBUGGING *product* is deliberately NOT advertised here: it
            # is added to the live client when DI actually starts (see
            # DI::Remote.handle_rc_enablement and Components#startup!) and removed
            # when it stops. Advertising it at startup would make every candidate
            # tracer subscribe, which the backend heartbeat monitor counts as an
            # active DI client. The receiver stays registered and gates on
            # component.started?, ignoring configs while DI is stopped.
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
                # Advertise the product at startup only when Symbol Database is
                # explicitly enabled (independent of DI). When it mirrors DI
                # (setting left at default nil), defer the product like
                # LIVE_DEBUGGING: DI::Remote.deferred_products adds it on DI start.
                unless settings.symbol_database.using_default?(:enabled)
                  register_products(Datadog::SymbolDatabase::Remote.products)
                end
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
