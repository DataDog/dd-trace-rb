require 'datadog/tracing/contrib/aws/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Aws::Configuration::Settings do
  it_behaves_like 'service name setting', 'aws'
end
