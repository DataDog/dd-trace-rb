require 'datadog/tracing/contrib/httpclient/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Httpclient::Configuration::Settings do
  it_behaves_like 'service name setting', 'httpclient'
end
