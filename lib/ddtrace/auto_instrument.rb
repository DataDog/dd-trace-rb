require 'ddtrace'

module Datadog
  # AutoInstrumentation enables all integrations
  module AutoInstrument
    module_function

    def patch_all
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

    if Datadog::Contrib::Rails::Utils.railtie_supported?
      # Railtie to include AutoInstrumentation in rails loading
      class Railtie < Rails::Railtie
        # we want to load before config initializers so that any user supplied config
        # in config/initializers/datadog.rb will take precedence
        initializer 'datadog.start_tracer', before: :load_config_initializers do
          AutoInstrument.patch_all
        end
      end
    else
      patch_all
    end
  end
end
