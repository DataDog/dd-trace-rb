require 'datadog/tracing/contrib/pg/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Pg::Configuration::Settings do
  it_behaves_like 'service name setting', 'pg'
end
