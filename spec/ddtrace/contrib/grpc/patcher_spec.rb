# typed: false
require 'ddtrace/contrib/support/spec_helper'

require 'grpc'
require 'ddtrace'
require 'ddtrace/contrib/grpc/patcher'

RSpec.describe 'GRPC instrumentation' do
  include_context 'tracer logging'

  let(:configuration_options) { {} }

  # Enable the test tracer
  before do
    Datadog::Tracing.configure do |c|
      c.instrument :grpc, configuration_options
    end
  end

  # TODO: Test Patcher#patch
end
