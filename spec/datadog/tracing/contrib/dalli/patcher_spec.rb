require 'datadog/tracing/contrib/support/spec_helper'

require 'dalli'
require 'ddtrace'
require 'datadog/tracing/contrib/dalli/patcher'

RSpec.describe 'Dalli instrumentation' do
  include_context 'tracer logging'

  let(:configuration_options) { {} }

  # Enable the test tracer
  before do
    Datadog.configure do |c|
      c.tracing.instrument :dalli, configuration_options
    end
  end

  # TODO: Test Patcher#patch
end
