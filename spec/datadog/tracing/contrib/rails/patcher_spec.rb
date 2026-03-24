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

    it 'sets up the tracer' do
      described_class.after_initialize(app)

      expect(described_class).to have_received(:setup_tracer)
    end

    it 'only sets up the tracer once per app' do
      described_class.after_initialize(app)
      described_class.after_initialize(app)

      expect(described_class).to have_received(:setup_tracer).once
    end
  end
end
