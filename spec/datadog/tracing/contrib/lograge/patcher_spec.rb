require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'lograge'
require 'datadog/tracing/contrib/lograge/patcher'

RSpec.describe Datadog::Tracing::Contrib::Lograge::Patcher do
  describe '.patch' do
    it 'adds Instrumentation to ancestors of LogSubscribers::Base class' do
      described_class.patch

      expect(Lograge::LogSubscribers::Base.ancestors).to include(Datadog::Tracing::Contrib::Lograge::Instrumentation)
    end
  end
end
