require 'datadog/tracing/contrib/excon/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Excon::Configuration::Settings do
  it_behaves_like 'service name setting', 'excon'
end
