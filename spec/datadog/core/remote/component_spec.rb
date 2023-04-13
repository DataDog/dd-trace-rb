# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/component'

RSpec.describe Datadog::Core::Remote::Component do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  describe '#initialize' do
    subject(:component) { described_class.new(settings, agent_settings) }

    let(:transport_v7) { double }
    let(:client) { double }
    let(:worker) { component.instance_eval { @worker } }

    before do
      expect(Datadog::Core::Transport::HTTP).to receive(:v7).and_return(transport_v7)
      expect(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

      expect(worker).to receive(:start).and_call_original
      expect(worker).to receive(:stop).and_call_original
    end

    after do
      component.shutdown!
    end

    context 'when client sync succeeds' do
      before do
        expect(worker).to receive(:call).and_call_original
        expect(client).to receive(:sync).and_return(nil)
      end

      it 'does not log any error' do
        expect(Datadog.logger).to_not receive(:error)

        component.barrier(:once)
      end
    end

    context 'when client sync raises' do
      let(:second_client) { double }
      let(:exception) { Class.new(StandardError) }

      before do
        expect(worker).to receive(:call).and_call_original
        expect(client).to receive(:sync).and_raise(exception, 'test')
        allow(Datadog.logger).to receive(:error).and_return(nil)
      end

      it 'logs an error' do
        allow(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

        expect(Datadog.logger).to receive(:error).and_return(nil)

        component.barrier(:once)
      end

      it 'catches exceptions' do
        allow(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

        # if the error is uncaught it will crash the test, so a mere passing is good

        component.barrier(:once)
      end

      it 'creates a new client' do
        expect(Datadog::Core::Remote::Client).to receive(:new).and_return(second_client)

        expect(component.client.object_id).to eql(client.object_id)

        component.barrier(:once)

        expect(component.client.object_id).to eql(second_client.object_id)
      end
    end
  end
end

RSpec.describe Datadog::Core::Remote::Component::Barrier do
  let(:delay) { 0.5 }

  subject(:barrier) { described_class.new }

  shared_context('recorder') do
    let(:record) { [] }
  end

  shared_context('waiter thread') do
    include_context 'recorder'

    let(:thr) do
      Thread.new do
        loop do
          record << :wait
          barrier.wait_next
        end
      end
    end

    before do
      thr.run
    end

    after do
      thr.kill
      thr.join
    end
  end

  shared_context('lifter thread') do
    include_context 'recorder'

    let(:thr) do
      Thread.new do
        loop do
          sleep delay
          record << :lift
          barrier.lift
        end
      end
    end

    before do
      record
      thr.run
    end

    after do
      thr.kill
      thr.join
    end
  end

  describe '#lift' do
    context 'without waiters' do
      include_context 'recorder'

      it 'does not block' do
        record << :one
        barrier.lift
        record << :two

        expect(record).to eq [:one, :two]
      end
    end

    context 'with waiters' do
      include_context 'waiter thread'

      it 'unblocks waiters' do
        sleep delay
        record << :one
        barrier.lift

        sleep delay
        record << :two
        barrier.lift

        # there may be an additional :wait if waiter thread gets switched to
        recorded = record[0, 4]

        expect(recorded).to eq [:wait, :one, :wait, :two]
      end
    end
  end

  describe '#wait_once' do
    include_context 'lifter thread'

    it 'blocks once' do
      record << :one
      barrier.wait_once
      record << :two

      expect(record).to eq [:one, :lift, :two]
    end

    it 'blocks only once' do
      record << :one
      barrier.wait_once
      record << :two
      barrier.wait_once
      record << :three

      expect(record).to eq [:one, :lift, :two, :three]
    end
  end

  describe '#wait_next' do
    include_context 'lifter thread'

    it 'blocks once' do
      record << :one
      barrier.wait_next
      record << :two

      expect(record).to eq [:one, :lift, :two]
    end

    it 'blocks each time' do
      record << :one
      barrier.wait_next
      record << :two
      barrier.wait_next
      record << :three

      expect(record).to eq [:one, :lift, :two, :lift, :three]
    end
  end
end
