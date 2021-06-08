require 'ddtrace'

module Datadog
  module Contrib
    # Extensions for auto instrumentation added to the base library
    # AutoInstrumentation enables all integration
    module AutoInstrument
      def self.extended(base)
        base.extend(Patch)
      end

      # Patch adds method for invoking auto_instrumentation
      module Patch
        def add_auto_instrument
          super

          if Datadog::Contrib::Rails::Utils.railtie_supported?
            require 'ddtrace/contrib/rails/auto_instrument_railtie'
          else
            AutoInstrument.patch_all
          end
        end
      end

      def self.patch_all
        integrations = []

        Datadog.registry.each do |integration|
          # some instrumentations are automatically enabled when the `rails` instrumentation is enabled,
          # patching them on their own automatically outside of the rails integration context would
          # cause undesirable service naming, so we exclude them based their auto_instrument? setting.
          # we also don't want to mix rspec/cucumber integration in as rspec is env we run tests in.
          next unless integration.klass.auto_instrument?

          integrations << integration.name
        end

        Datadog.configure do |c|
          c.reduce_log_verbosity
          # This will activate auto-instrumentation for Rails
          integrations.each do |integration_name|
            c.use integration_name
          end
        end
      end
    end
  end
end
