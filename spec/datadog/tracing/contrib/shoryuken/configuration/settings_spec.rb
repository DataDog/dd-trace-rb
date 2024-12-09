require 'datadog/tracing/contrib/shoryuken/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Shoryuken::Configuration::Settings do
  it_behaves_like 'with on_error setting'
end
