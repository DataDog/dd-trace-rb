# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures'

RSpec.describe Datadog::OpenFeature::Exposures::Worker do
  subject(:worker) do
    described_class.new(
      transport: transport,
      logger: logger,
      flush_interval_seconds: flush_interval,
      buffer_limit: buffer_limit,
      context_builder: context_builder
    )
  end

  let(:logger) { Datadog.logger }
  let(:transport) { instance_double('transport') }
  let(:response) { instance_double('response', ok?: true) }
  let(:context_builder) { -> { {} } }
  let(:flush_interval) { 60 }
  let(:buffer_limit) { 1 }
  let(:event) do
    Datadog::OpenFeature::Exposures::Event.new(
      timestamp: Time.utc(2024, 1, 1),
      allocation_key: 'control',
      flag_key: 'demo-flag',
      variant_key: 'v1',
      subject_id: 'user-1'
    )
  end

  before do
    allow(transport).to receive(:send_exposures).and_return(response)
    allow(worker).to receive(:start)
  end

  describe '#enqueue' do
    it do
      expect(transport).to receive(:send_exposures) do |payload|
        exposures = payload.fetch(:exposures)
        expect(exposures.length).to eq(1)
        expect(exposures.first[:flag][:key]).to eq('demo-flag')
      end.and_return(response)

      worker.enqueue(event)
    end
  end

  describe '#flush' do
    let(:buffer_limit) { 2 }

    it do
      worker.enqueue(event)

      expect(transport).to receive(:send_exposures).once.and_return(response)

      worker.flush
    end
  end

  describe '#stop' do
    let(:buffer_limit) { 2 }

    it do
      worker.enqueue(event)

      expect(transport).to receive(:send_exposures).once.and_return(response)

      worker.stop
    end
  end
end

