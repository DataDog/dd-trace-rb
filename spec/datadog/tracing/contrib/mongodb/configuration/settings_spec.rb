require 'datadog/tracing/contrib/mongodb/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::MongoDB::Configuration::Settings do
  it_behaves_like 'service name setting', 'mongodb'
end
