require 'datadog/tracing/contrib/redis/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Redis::Configuration::Settings do
  it_behaves_like 'service name setting', 'redis'
end
