require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog'
require 'lograge'
require 'datadog/tracing/contrib/lograge/patcher'

RSpec.describe Datadog::Tracing::Contrib::Lograge::Patcher do
  describe '.patch' do
    before { described_class.instance_variable_get(:@patch_only_once)&.reset }

    it 'adds Instrumentation to ancestors of LogSubscribers::Base class' do
      described_class.patch

      expect(Lograge::LogSubscribers::Base.ancestors).to include(Datadog::Tracing::Contrib::Lograge::Instrumentation)
    end

    context 'without Rails tagged logging' do
      it 'does not log incompatibility error' do
        expect(Datadog.logger).to_not receive(:warn)

        described_class.patch
      end
    end

    context 'with tagged logging for the Lograge logger' do
      before do
        logger = ActiveSupport::TaggedLogging.new(Logger.new(File::NULL))
        allow(::Lograge).to receive(:logger).and_return(logger)
      end

      it 'logs an incompatibility error' do
        expect(Datadog.logger).to receive(:warn).with(/ActiveSupport::TaggedLogging/)

        described_class.patch
      end
    end

    context 'with tagged logging for the Rails logger' do
      before do
        logger = ActiveSupport::TaggedLogging.new(Logger.new(File::NULL))
        stub_const('Lograge::LogSubscribers::ActionController', double('controller', logger: logger))
      end

      it 'logs an incompatibility error' do
        expect(Datadog.logger).to receive(:warn).with(/ActiveSupport::TaggedLogging/)

        described_class.patch
      end

      context 'when the Lograge logger does not use tagged logging' do
        before do
          logger = ActiveSupport::Logger.new(File::NULL)
          allow(::Lograge).to receive(:logger).and_return(logger)
        end

        it 'does not log incompatibility error' do
          expect(Datadog.logger).to_not receive(:warn)

          described_class.patch
        end
      end
    end
  end
end
