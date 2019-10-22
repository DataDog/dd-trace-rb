RSpec.shared_context 'trace context' do
  let(:context) { instance_double(Datadog::Context, get: get) }

  let(:get) { [trace, sampled] }
  let(:sampled) { true }
  let(:trace) { [double] }
end

RSpec.shared_examples_for 'a context flusher' do
  context 'with request not sampled' do
    let(:sampled) { false }

    it 'returns nil' do
      is_expected.to be_nil
    end
  end

  context 'with request sampled' do
    let(:sampled) { true }

    it 'returns the original trace' do
      is_expected.to eq(trace)
    end
  end
end
