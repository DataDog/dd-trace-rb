# typed: false
require 'ddtrace/contrib/support/spec_helper'

require 'dalli'
require 'ddtrace'
require 'ddtrace/contrib/dalli/patcher'

RSpec.describe 'Dalli instrumentation' do
  include_context 'tracer logging'

  let(:configuration_options) { {} }

  # Enable the test tracer
  before do
    Datadog::Tracing.configure do |c|
      c.instrument :dalli, configuration_options
    end
  end

  # TODO: Test Patcher#patch
end
