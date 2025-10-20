require 'datadog/tracing/contrib/grape/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Grape::Configuration::Settings do
  it_behaves_like 'with on_error setting'
  it_behaves_like 'with error_status_codes setting', env: 'DD_TRACE_GRAPE_ERROR_STATUS_CODES', default: 500...600, settings_class: described_class, option: :error_status_codes, global_config: {server: 710..719}
end
