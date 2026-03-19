# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/contrib/rails/patcher'

RSpec.describe Datadog::Tracing::Contrib::Rails::Patcher do
  describe '.after_initialize' do
    let(:app) { double('application') }

    before do
      described_class::AFTER_INITIALIZE_ONLY_ONCE_PER_APP.delete(app)
      allow(described_class).to receive(:setup_tracer)
    end

    context 'when process tags are enabled' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(true)
        allow(Datadog::Core::Environment::Process).to receive(:recompute_tags!)
      end

      it 'recomputes the process tags' do
        described_class.after_initialize(app)

        expect(Datadog::Core::Environment::Process).to have_received(:recompute_tags!)
      end
    end

    context 'when process tags are not enabled' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
        allow(Datadog::Core::Environment::Process).to receive(:recompute_tags!)
      end

      it 'does not recompute the process tags' do
        described_class.after_initialize(app)

        expect(Datadog::Core::Environment::Process).to_not have_received(:recompute_tags!)
      end
    end
  end
end
