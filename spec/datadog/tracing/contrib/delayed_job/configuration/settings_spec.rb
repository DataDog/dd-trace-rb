require 'datadog/tracing/contrib/delayed_job/configuration/settings'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::DelayedJob::Configuration::Settings do
  it_behaves_like 'with on_error setting'
end
