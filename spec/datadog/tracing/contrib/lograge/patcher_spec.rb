require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog'
require 'lograge'
require 'datadog/tracing/contrib/lograge/patcher'

RSpec.describe Datadog::Tracing::Contrib::Lograge::Patcher do
  describe '.patch' do
    before { described_class.instance_variable_get(:@patch_only_once)&.send(:reset_ran_once_state_for_tests) }

    it 'adds Instrumentation to ancestors of LogSubscribers::Base class' do
      described_class.patch

      expect(Lograge::LogSubscribers::Base.ancestors).to include(Datadog::Tracing::Contrib::Lograge::Instrumentation)
    end

    context 'without Rails tagged logging' do
      it 'does not log incompatibility error' do
        expect(Datadog.logger).to_not receive(:error)

        described_class.patch
      end
    end

    context 'with Rails tagged logging' do
      it 'logs an incompatibility error' do
        logger = ActiveSupport::TaggedLogging.new(Logger.new(File::NULL))
        stub_const('Lograge::LogSubscribers::ActionController', double('controller', logger: logger))

        expect(Datadog.logger).to receive(:error).with(/ActiveSupport::TaggedLogging/)

        described_class.patch
      end
    end
  end
end
