require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'lograge'
require 'ddtrace/contrib/lograge/patcher'

RSpec.describe Datadog::Contrib::Lograge::Patcher do
  describe '.patch' do
    it 'adds Instrumentation to ancestors of LogSubscribers::Base class' do
      described_class.patch

      expect(Lograge::LogSubscribers::Base.ancestors).to include(Datadog::Contrib::Lograge::Instrumentation)
    end
  end
end
