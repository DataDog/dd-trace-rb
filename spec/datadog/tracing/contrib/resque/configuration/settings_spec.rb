require 'datadog/tracing/contrib/resque/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::Resque::Configuration::Settings do
  it_behaves_like 'with on_error setting'
end
