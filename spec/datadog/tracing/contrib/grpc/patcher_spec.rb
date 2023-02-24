require 'datadog/tracing/contrib/support/spec_helper'

require 'grpc'
require 'ddtrace'
require 'datadog/tracing/contrib/grpc/patcher'

RSpec.describe 'GRPC instrumentation' do
  include_context 'tracer logging'

  let(:configuration_options) { {} }

  # Enable the test tracer
  before do
    Datadog.configure do |c|
      c.tracing.instrument :grpc, configuration_options
    end
  end

  # TODO: Test Patcher#patch
end
