# frozen_string_literal: true

require 'rspec'

RSpec.describe Datadog::Tracing::Component do
  describe 'writer event callbacks' do
    describe Datadog::Tracing::Component::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK do
      subject(:call) { described_class.call(writer, responses) }
      let(:writer) { double('writer') }
      let(:responses) { [double('response')] }

      before do
        Datadog::Tracing::Component::WRITER_RECORD_ENVIRONMENT_INFORMATION_ONLY_ONCE.send(:reset_ran_once_state_for_tests)
      end

      it 'invokes the environment logger with responses' do
        expect(Datadog::Tracing::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!).with(responses: responses)
        call
      end

      it 'invokes the environment logger only once' do
        expect(Datadog::Tracing::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!).once

        described_class.call(writer, responses)
        described_class.call(writer, responses)
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Component::SamplerDelegatorComponent do
  let(:delegator) { described_class.new(old_sampler) }
  let(:old_sampler) { double('initial') }
  let(:new_sampler) { double('new') }

  let(:trace) { double('trace') }

  it 'changes instance on sampler=' do
    expect { delegator.sampler = new_sampler }.to change { delegator.sampler }.from(old_sampler).to(new_sampler)
  end

  it 'delegates #sample! to the internal sampler' do
    expect(old_sampler).to receive(:sample!).with(trace)
    delegator.sample!(trace)
  end

  it 'delegates #update to the internal sampler' do
    expect(old_sampler).to receive(:update).with(1, 2, a: 3, b: 4)
    delegator.update(1, 2, a: 3, b: 4)
  end

  it "does not delegate #update when internal sampler doesn't support it" do
    delegator.update(1, 2, a: 3, b: 4)
  end
end
