require 'datadog/tracing/contrib/mysql2/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Mysql2::Configuration::Settings do
  it_behaves_like 'service name setting', 'mysql2'
end
