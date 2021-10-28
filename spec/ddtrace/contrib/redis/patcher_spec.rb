# typed: false
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Contrib::Redis::Patcher do
  describe '.patch' do
    it 'adds Instrumentation methods to ancestors of Redis class' do
      described_class.patch

      expect(Redis::Client.ancestors).to include(Datadog::Contrib::Redis::Instrumentation)
      expect(Redis::Client.ancestors).to include(Datadog::Contrib::Redis::Instrumentation)
    end
  end
end
