require 'ddtrace'

module Datadog
  # AutoInstrumentation enables all integrations
  module AutoInstrument
    module_function

    def patch_all
      integrations = []
      Datadog.registry.each do |integration|
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

    if Datadog::Utils::Rails.railtie_supported?
      # Railtie to include AutoInstrumentation in rails loading
      class Railtie < Rails::Railtie
        # we want to load before config initializers so that any user supplied config
        # in config/initializers/datadog.rb will take precedence
        initializer 'datadog.start_tracer', before: :load_config_initializers do
          # some instrumentations are automatically enabled when the `rails` instrumentation is enabled,
          # patching them on their own automatically outside of the
          # rails integration context would cause their service name
          # details not to be set correctly, so we exclude them
          # we also don't want to mix rspec/cucumber integration in as rspec is env we run tests in
          AutoInstrument.patch_all
        end
      end
    else
      # we don't want to mix rspec/cucumber integration in as rspec is framework we run tests in
      patch_all
    end
  end
end
