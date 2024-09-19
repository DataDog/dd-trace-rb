require 'datadog/tracing/contrib/presto/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Presto::Configuration::Settings do
  it_behaves_like 'service name setting', 'presto'
end
