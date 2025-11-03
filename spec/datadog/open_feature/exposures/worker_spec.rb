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

  let(:logger) { logger_allowing_debug }
  let(:transport) { instance_double('transport') }
  let(:response) { instance_double('response', ok?: true) }
  let(:context_builder) { -> { {} } }
  let(:flush_interval) { 0.1 }
  let(:buffer_limit) { 2 }
  let(:event) do
    Datadog::OpenFeature::Exposures::Event.new(
      timestamp: Time.utc(2024, 1, 1),
      allocation_key: 'control',
      flag_key: 'demo-flag',
      variant_key: 'v1',
      subject_id: 'user-1'
    )
  end

  after do
    worker.stop(true)
    worker.join
  end

  describe '#start' do
    it 'does nothing when disabled' do
      worker.enabled = false

      worker.start

      expect(worker).not_to be_running
      expect(worker).not_to be_started
    end

    it 'starts on demand and processes buffer' do
      sent = 0
      allow(transport).to receive(:send_exposures) do |payload|
        sent += 1
        response
      end

      worker.enqueue(event)

      try_wait_until { worker.running? }
      try_wait_until { sent.positive? }

      expect(sent).to eq(1)
    end
  end

  describe '#enqueue' do
    before do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
    end

    it 'flushes immediately when buffer limit reached' do
      expect(transport).to receive(:send_exposures).once.and_return(response)

      worker.enqueue(event)
      worker.enqueue(event)

      try_wait_until { worker.buffer.empty? }
    end
  end

  describe '#flush' do
    let(:buffer_limit) { 3 }

    before do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
    end

    it 'sends queued events' do
      worker.enqueue(event)
      worker.enqueue(event)

      worker.flush

      expect(transport).to have_received(:send_exposures).once
    end
  end

  describe '#stop' do
    before do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
    end

    it 'flushes remaining events before stopping' do
      worker.enqueue(event)

      expect(transport).to receive(:send_exposures).once.and_return(response)

      worker.stop
    end
  end
end

