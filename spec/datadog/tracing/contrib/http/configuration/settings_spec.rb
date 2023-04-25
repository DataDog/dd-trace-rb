require 'datadog/tracing/contrib/http/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Configuration::Settings do
  it_behaves_like 'service name setting', 'net/http'
end
