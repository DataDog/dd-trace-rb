require 'datadog/tracing/contrib/trilogy/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Trilogy::Configuration::Settings do
  it_behaves_like 'service name setting', 'trilogy'
end
