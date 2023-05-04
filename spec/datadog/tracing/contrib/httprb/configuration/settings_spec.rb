require 'datadog/tracing/contrib/httprb/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Httprb::Configuration::Settings do
  it_behaves_like 'service name setting', 'httprb'
end
