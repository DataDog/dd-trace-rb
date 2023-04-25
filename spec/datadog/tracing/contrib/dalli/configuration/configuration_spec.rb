require 'datadog/tracing/contrib/dalli/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Dalli::Configuration::Settings do
  it_behaves_like 'service name setting', 'memcached'
end
