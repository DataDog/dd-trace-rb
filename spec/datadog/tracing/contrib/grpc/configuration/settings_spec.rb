require 'datadog/tracing/contrib/grpc/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Configuration::Settings do
  it_behaves_like 'service name setting', 'grpc'
end
