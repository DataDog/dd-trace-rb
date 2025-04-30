require 'datadog/tracing/contrib/grpc/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Configuration::Settings do
  it_behaves_like 'service name setting', 'grpc'
  it_behaves_like 'with on_error setting'
end
