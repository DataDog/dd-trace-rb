require 'datadog/tracing/contrib/elasticsearch/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Elasticsearch::Configuration::Settings do
  it_behaves_like 'service name setting', 'elasticsearch'
end
