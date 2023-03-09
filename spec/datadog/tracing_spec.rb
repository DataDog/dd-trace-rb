require 'spec_helper'

require 'datadog/statsd'

# All the doubles in this file are simple pass through values.
# There's no value in making them verifying doubles.
RSpec.describe Datadog::Tracing do
  let(:returned) { double('delegated return value') }

  describe '.active_span' do
    subject(:active_span) { described_class.active_span }

    it 'delegates to the tracer' do
      expect(Datadog.send(:components).tracer).to receive(:active_span).and_return(returned)
      expect(active_span).to eq(returned)
    end
  end

  describe '.active_trace' do
    subject(:active_trace) { described_class.active_trace }

    it 'delegates to the tracer' do
      expect(Datadog.send(:components).tracer).to receive(:active_trace)
      active_trace
    end
  end

  describe '.keep!' do
    subject(:keep!) { described_class.keep! }

    context 'with an active trace' do
      let!(:trace) do
        described_class.trace('test.trace')
      end

      it 'delegates to the active trace' do
        expect(Datadog.send(:components).tracer.active_trace).to receive(:keep!)
        keep!
      end
    end

    context 'without an active trace' do
      it 'does not perform any operation' do
        expect { keep! }.to_not raise_error
      end
    end
  end

  describe '.continue_trace!' do
    subject(:continue_trace!) { described_class.continue_trace!(digest, &block) }
    let(:digest) { double('digest') }
    let(:block) { -> {} }

    it 'delegates to the tracer' do
      expect(Datadog.send(:components).tracer).to receive(:continue_trace!)
        .with(digest) { |&b| expect(b).to be(block) }.and_return(returned)
      expect(continue_trace!).to eq(returned)
    end
  end

  describe '.trace' do
    subject(:trace) { described_class.trace(name, continue_from: continue_from, **span_options, &block) }
    let(:name) { double('name') }
    let(:continue_from) { double('continue_from') }
    let(:span_options) { { resource: double('option') } }
    let(:block) { -> {} }

    it 'delegates to the tracer' do
      expect(Datadog.send(:components).tracer).to receive(:trace)
        .with(name, continue_from: continue_from, **span_options) { |&b| expect(b).to be(block) }
        .and_return(returned)
      expect(trace).to eq(returned)
    end
  end

  describe '.reject!' do
    subject(:reject!) { described_class.reject! }
    context 'with an active trace' do
      let!(:trace) do
        described_class.trace('test.trace')
      end

      it 'delegates to the active trace' do
        expect(Datadog.send(:components).tracer.active_trace).to receive(:reject!).and_return(returned)
        expect(reject!).to eq(returned)
      end
    end

    context 'without an active trace' do
      it 'does not perform any operation' do
        expect { reject! }.to_not raise_error
      end
    end
  end

  describe '.log_correlation' do
    subject(:log_correlation) { described_class.log_correlation }

    # rubocop:disable RSpec/MessageChain
    it 'delegates to the active correlation' do
      # DEV: Datadog::Tracer#active_correlation returns a new object on every invocation.
      # Once we memoize `Datadog::Correlation#identifier_from_digest`, we can simplify this
      # `receive_message_chain` assertion to `expect(Datadog.tracer.active_correlation).to receive(:to_log_format)`
      expect(Datadog.send(:components).tracer).to receive_message_chain(:active_correlation, :to_log_format)
        .and_return(returned)
      expect(log_correlation).to eq(returned)
    end
    # rubocop:enable RSpec/MessageChain
  end

  describe '.shutdown!' do
    subject(:shutdown!) { described_class.shutdown! }
    it 'delegates to global components' do
      allow(Datadog.send(:components).tracer).to receive(:shutdown!)

      shutdown!

      expect(Datadog.send(:components).tracer).to have_received(:shutdown!)
    end
  end

  describe '.logger' do
    subject(:logger) { described_class.logger }
    it 'returns the global logger' do
      expect(logger).to be(Datadog.logger)
    end
  end

  describe '.correlation' do
    subject(:correlation) { described_class.correlation }
    it 'delegates to the tracer' do
      expect(described_class.send(:tracer)).to receive(:active_correlation).and_return(returned)
      expect(correlation).to eq(returned)
    end
  end

  describe '.before_flush' do
    subject(:before_flush) { described_class.before_flush(*processors, &block) }
    let(:processors) { [double('processor')] }
    let(:block) { -> {} }
    it 'delegates to the global pipeline' do
      expect(Datadog::Tracing::Pipeline).to receive(:before_flush).with(*processors) { |&b| expect(b).to be(block) }
      before_flush
    end
  end

  describe '.enabled?' do
    subject(:enabled?) { described_class.enabled? }
    it 'delegates to the tracer' do
      expect(described_class.send(:tracer)).to receive(:enabled)
      enabled?
    end
  end
end
