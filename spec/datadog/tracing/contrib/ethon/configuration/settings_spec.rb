require 'datadog/tracing/contrib/ethon/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Ethon::Configuration::Settings do
  it_behaves_like 'service name setting', 'ethon'
end
