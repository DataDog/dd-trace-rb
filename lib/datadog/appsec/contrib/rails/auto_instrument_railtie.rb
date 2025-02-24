# rubocop:disable Naming/FileName
# frozen_string_literal: true

# Railtie to include AutoInstrumentation in rails loading
class DatadogAutoInstrumentRailtie < Rails::Railtie
  # we want to load before config initializers so that any user supplied config
  # in config/initializers/datadog.rb will take precedence
  initializer 'datadog.start_appsec', before: :load_config_initializers do
    Datadog::AppSec::Contrib::AutoInstrument.patch_all!
  end
end
# rubocop:enable Naming/FileName
