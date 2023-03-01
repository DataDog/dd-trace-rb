require 'ddtrace'
require 'datadog/appsec'
require 'spec_helper'

RSpec.configure do |config|
  # As AppSec is disabled by default, activate it using the environment variable DD_APPSEC_ENABLED.
  config.before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DD_APPSEC_ENABLED').and_return('true')
  end
end
