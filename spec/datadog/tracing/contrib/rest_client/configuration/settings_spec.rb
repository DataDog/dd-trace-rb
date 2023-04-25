require 'datadog/tracing/contrib/rest_client/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::RestClient::Configuration::Settings do
  it_behaves_like 'service name setting', 'rest_client'
end
