# typed: false
require 'ddtrace/contrib/support/spec_helper'

require 'faraday'
require 'ddtrace'
require 'ddtrace/contrib/faraday/patcher'

RSpec.describe 'Faraday instrumentation' do
  include_context 'tracer logging'

  let(:configuration_options) { {} }

  # Enable the test tracer
  before do
    Datadog::Tracing.configure do |c|
      c.instrument :faraday, configuration_options
    end
  end

  # TODO: Test Patcher#patch
end
