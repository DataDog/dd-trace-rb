require "datadog/tracing/contrib/trilogy/configuration/settings"
require "datadog/tracing/contrib/service_name_settings_examples"
require "datadog/tracing/contrib/shared_settings_examples"

RSpec.describe Datadog::Tracing::Contrib::Trilogy::Configuration::Settings do
  it_behaves_like "service name setting", "trilogy"
  it_behaves_like "with on_error setting"
end
