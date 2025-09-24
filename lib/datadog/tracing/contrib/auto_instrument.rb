# frozen_string_literal: true

require_relative '../contrib'
require_relative 'extensions'

module Datadog
  module Tracing
    # Out-of-the-box instrumentation for tracing
    module Contrib
      # Auto-activate instrumentation
      def self.auto_instrument!
        require_relative '../../core/contrib/rails/utils'

        # Defer to Rails if this is a Rails application
        if Datadog::Core::Contrib::Rails::Utils.railtie_supported?
          require_relative 'rails/auto_instrument_railtie'
        else
          AutoInstrument.patch_all!
        end
      end

      # Extensions for auto instrumentation added to the base library
      # AutoInstrumentation enables all integration
      module AutoInstrument
        def self.patch_all!
          puts "🔍 [AUTO-INSTRUMENT] Starting auto-instrumentation..."
          integrations = []

          Contrib::REGISTRY.each do |integration|
            puts "🔍 [AUTO-INSTRUMENT] Checking integration: #{integration.name}"
            puts "🔍 [AUTO-INSTRUMENT] - auto_patch: #{integration.auto_patch}"
            puts "🔍 [AUTO-INSTRUMENT] - klass: #{integration.klass}"
            puts "🔍 [AUTO-INSTRUMENT] - auto_instrument?: #{integration.klass.auto_instrument? rescue 'ERROR'}"
            puts "🔍 [AUTO-INSTRUMENT] - loaded?: #{integration.klass.loaded? rescue 'ERROR'}"
            puts "🔍 [AUTO-INSTRUMENT] - compatible?: #{integration.klass.compatible? rescue 'ERROR'}"
            
            # some instrumentations are automatically enabled when the `rails` instrumentation is enabled,
            # patching them on their own automatically outside of the rails integration context would
            # cause undesirable service naming, so we exclude them based their auto_instrument? setting.
            # we also don't want to mix rspec/cucumber integration in as rspec is env we run tests in.
            if integration.klass.auto_instrument?
              integrations << integration.name
              puts "🔍 [AUTO-INSTRUMENT] ✅ Added #{integration.name} to auto-instrumentation list"
            else
              puts "🔍 [AUTO-INSTRUMENT] ❌ Skipped #{integration.name} (auto_instrument? = false)"
            end
          end

          puts "🔍 [AUTO-INSTRUMENT] Total integrations to auto-instrument: #{integrations.length}"
          puts "🔍 [AUTO-INSTRUMENT] Integrations: #{integrations.inspect}"

          Datadog.configure do |c|
            # Ignore any instrumentation load errors (otherwise it might spam logs)
            c.tracing.ignore_integration_load_errors = true

            # Activate instrumentation for each integration
            integrations.each do |integration_name|
              puts "🔍 [AUTO-INSTRUMENT] Activating #{integration_name}..."
              begin
                c.tracing.instrument integration_name
                puts "🔍 [AUTO-INSTRUMENT] ✅ Successfully activated #{integration_name}"
              rescue => e
                puts "🔍 [AUTO-INSTRUMENT] ❌ Failed to activate #{integration_name}: #{e.message}"
              end
            end
          end
          
          puts "🔍 [AUTO-INSTRUMENT] Auto-instrumentation complete"
        end
      end
    end
  end
end

Datadog::Tracing::Contrib.auto_instrument!
