require 'datadog/tracing/contrib/racecar/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Racecar::Configuration::Settings do
  it_behaves_like 'service name setting', 'racecar'
end
