RSpec.describe Datadog::Tracing do
  context '.active_span' do
    subject(:active_span) { described_class.active_span }

    context 'with an active span' do
      let!(:span) do
        described_class.trace('test.trace')
      end

      it 'returns active span from global tracer' do
        expect(active_span).to be(span)
      end
    end

    context 'without an active span' do
      it { expect(active_span).to be_nil }
    end
  end

  context '.active_trace' do
    subject(:active_trace) { described_class.active_trace }

    context 'with an active trace' do
      let!(:span) do
        described_class.trace('test.trace')
      end

      it 'returns active trace from global tracer' do
        expect(active_trace).to be(Datadog.tracer.active_trace)
      end
    end

    context 'without an active trace' do
      it { expect(active_trace).to be_nil }
    end
  end

  context '.keep!' do
    subject(:keep!) { described_class.keep! }
    context 'with an active trace' do
      let!(:trace) do
        described_class.trace('test.trace')
        described_class.active_trace.reject!
        described_class.active_trace
      end

      it 'changes trace sampling decision to true' do
        expect { keep! }.to change { trace.sampled? }.from(false).to(true)
      end
    end

    context 'without an active trace' do
      it 'does not perform any operation' do
        expect { keep! }.to_not raise_error
      end
    end
  end

  context '.continue_trace!' do
    subject(:continue_trace!) { described_class.continue_trace!(digest, &block) }
    let(:digest) { Datadog::TraceDigest.new(span_id: span_id, trace_id: trace_id) }
    let(:span_id) { double('span_id') }
    let(:trace_id) { double('trace_id') }

    context 'with a block' do
      let(:block) { -> { block_result } }
      let(:block_result) { double('result') }

      it 'returns the block result' do
        expect(continue_trace!).to eq(block_result)
      end
    end

    context 'without a block' do
      subject(:continue_trace!) { described_class.continue_trace!(digest) }

      it 'returns an unfinished span operation' do
        expect(continue_trace!).to be_a(Datadog::TraceOperation)
        expect(continue_trace!.parent_span_id).to eq(span_id)
        expect(continue_trace!.id).to eq(trace_id)
      end
    end
  end

  context '.trace' do
    let(:name) { 'test-name' }
    let(:continue_from) { nil }
    let(:span_options) { { my: :option } }

    context 'with a block' do
      subject(:trace) { described_class.trace(name, continue_from: continue_from, **span_options, &block) }
      let(:block) { ->(_span, _trace) { block_result } }
      let(:block_result) { double('result') }

      it 'invokes block with span and trace arguments' do
        expect { |b| described_class.trace(name, continue_from: continue_from, **span_options, &b) }
          .to yield_with_args(be_a(Datadog::SpanOperation), be_a(Datadog::TraceOperation))
      end

      it 'returns the block result' do
        expect(trace).to eq(block_result)
      end
    end

    context 'without a block' do
      subject(:trace) { described_class.trace(name, continue_from: continue_from, **span_options) }

      it 'returns an unfinished span operation' do
        expect(Datadog.tracer).to receive(:trace)
                                    .with(name, continue_from: continue_from, **span_options).and_call_original

        expect(trace).to be_a(Datadog::SpanOperation)
        expect(trace.name).to eq(name)
        expect(trace.finished?).to be_falsey
      end
    end
  end

  context '.reject!' do
    subject(:reject!) { described_class.reject! }
    context 'with an active trace' do
      let!(:trace) do
        described_class.trace('test.trace')
        described_class.active_trace.keep!
        described_class.active_trace
      end

      it 'changes trace sampling decision to false' do
        expect { reject! }.to change { trace.sampled? }.from(true).to(false)
      end
    end

    context 'without an active trace' do
      it 'does not perform any operation' do
        expect { reject! }.to_not raise_error
      end
    end
  end

  context '.tracer' do
    subject(:tracer) { described_class.tracer }
    it 'returns the global tracer' do
      expect(tracer).to be(Datadog.tracer)
    end
  end

  context '.log_correlation' do
    subject(:log_correlation) { described_class.log_correlation }
    it 'returns the current trace log correlation string' do
      expect(log_correlation).to be_a(String)
      expect(log_correlation).to include('dd.trace_id=')
    end
  end

  context '.configuration' do
    subject(:configuration) { described_class.configuration }
    it 'returns the global configuration' do
      expect(configuration).to eq(Datadog.configuration)
    end
  end

  context '.shutdown!' do
    subject(:shutdown!) { described_class.shutdown! }
    it 'shuts down global components' do
      allow(Datadog.send(:components)).to receive(:shutdown!)

      shutdown!

      expect(Datadog.send(:components)).to have_received(:shutdown!)
    end
  end

  context '.logger' do
    subject(:logger) { described_class.logger }
    it 'returns the global logger' do
      expect(logger).to be(Datadog.logger)
    end
  end

  context '.registry' do
    subject(:registry) { described_class.registry }
    it 'returns the global registry' do
      expect(registry).to eq(Datadog::Contrib::REGISTRY)
    end
  end

  context '.configure' do
    subject(:configure) { described_class.configure(&block) }
    let(:block) { ->(_c) { } }

    it 'invokes block with the global configuration as an argument' do
      expect { |b| described_class.configure(&b) }
        .to yield_with_args(described_class.configuration)
    end

    it 'restarts restarts components' do
      expect { configure }.to change{ described_class.tracer }
                                .from(described_class.tracer).to(not_be(described_class.tracer))
    end
  end

  context '.correlation' do
    subject(:correlation) { described_class.correlation }
    it 'returns the current trace correlation identifier' do
      expect(Datadog.tracer).to receive(:active_correlation).and_call_original
      expect(correlation).to be_a(Datadog::Correlation::Identifier)
    end
  end

  context '.before_flush' do
    pending do
    end
  end
end
