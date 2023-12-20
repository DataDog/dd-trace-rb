require 'datadog/tracing/contrib/http/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'
require 'datadog/tracing/contrib/shared_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Configuration::Settings do
  it_behaves_like 'service name setting', 'net/http'
  it_behaves_like 'with error_status_codes setting', env: 'DD_TRACE_HTTP_ERROR_STATUS_CODES'
end
