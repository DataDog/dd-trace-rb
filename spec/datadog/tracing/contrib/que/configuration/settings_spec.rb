require 'datadog/tracing/contrib/que/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Que::Configuration::Settings do
  it_behaves_like 'with on_error setting'
end
