# frozen_string_literal: true

module Datadog
  module AppSec
    # Contrib module includes all integrations
    module Contrib
      def self.auto_instrument!
        require_relative '../../core/contrib/rails/utils'

        # Auto-instrument via railtie if this is a Rails application
        if Datadog::Core::Contrib::Rails::Utils.railtie_supported?
          require_relative 'rails/auto_instrument_railtie'
        else
          AutoInstrument.patch_all!
        end
      end

      # Auto-instrumentation for security integrations
      module AutoInstrument
        module_function

        def patch_all!
          integrations = []

          Datadog::AppSec::Contrib::Integration.registry.each do |_name, integration|
            next unless integration.klass.auto_instrument?

            integrations << integration.name
          end

          integrations.each do |integration_name|
            Datadog.configuration.appsec.instrument integration_name
          end
        end
      end
    end
  end
end

if %w[1 true].include?((ENV['DD_APPSEC_ENABLED'] || '').downcase)
  begin
    Datadog::AppSec::Contrib.auto_instrument!
  rescue StandardError => e
    Kernel.warn(
      '[datadog] AppSec failed to instrument. No security check will be performed. error: ' \
      " #{e.class.name} #{e.message}"
    )
  end
end
