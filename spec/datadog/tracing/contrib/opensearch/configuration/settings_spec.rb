require 'datadog/tracing/contrib/opensearch/configuration/settings' # connecting to /lib/... ?
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::OpenSearch::Configuration::Settings do
  it_behaves_like 'service name setting', 'opensearch'
end
