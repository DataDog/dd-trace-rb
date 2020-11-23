require 'ddtrace'

module Datadog
  # AutoInstrumentation enables all integrations
  module AutoInstrument
    EXCLUDED_RAILS_INTEGRATIONS = [:rack, :action_cable, :active_support, :action_pack, :action_view, :active_record].freeze
    EXCLUDED_TEST_INTEGRATIONS = [:cucumber, :rspec].freeze

    module_function

    def patch_all(excluded_integratons = [])
      integrations = []
      Datadog.registry.each do |integration|
        next if excluded_integratons.include?(integration.name)
        integrations << integration.name
      end

      Datadog.configure(silence_logs: true) do |c|
        # This will activate auto-instrumentation for Rails
        integrations.each do |integration_name|
          c.use integration_name
        end
      end
    end

    if defined?(Rails) && defined?(Rails::VERSION) && defined?(Rails::VERSION::MAJOR) &&
       Rails::VERSION::MAJOR >= 3 &&
       defined?(Rails::Railtie)
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
          AutoInstrument.patch_all(EXCLUDED_RAILS_INTEGRATIONS + EXCLUDED_TEST_INTEGRATIONS)
        end
      end
    else
      # we don't want to mix rspec/cucumber integration in as rspec is framework we run tests in
      patch_all(EXCLUDED_TEST_INTEGRATIONS)
    end
  end
end
