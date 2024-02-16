# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/component'

RSpec.describe Datadog::Core::Remote::Component::Barrier do
  let(:delay) { 1.0 }
  let(:record) { [] }
  let(:timeout) { nil }
  let(:instance_timeout) { nil }

  subject(:barrier) { described_class.new(instance_timeout) }

  shared_context('lifter thread') do
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

  describe '#initialize' do
    it 'accepts one argument' do
      expect { described_class.new(instance_timeout) }.to_not raise_error
    end

    it 'accepts zero argument' do
      expect { described_class.new }.to_not raise_error
    end
  end

  describe '#lift' do
    context 'without waiters' do
      it 'does not block' do
        record << :one
        barrier.lift
        record << :two

        expect(record).to eq [:one, :two]
      end
    end

    context 'with waiters' do
      it 'unblocks waiters' do
        waiter_thread = Thread.new(record) do |record|
          record << :one
          expect(barrier.wait_once).to eq :lift
          record << :two
        end.run

        sleep delay

        record << :lift
        barrier.lift
        waiter_thread.join

        expect(record).to eq [:one, :lift, :two]
      end
    end
  end

  describe '#wait_once' do
    include_context 'lifter thread'

    it 'blocks once' do
      record << :one
      expect(barrier.wait_once).to eq :lift
      record << :two

      expect(record).to eq [:one, :lift, :two]
    end

    it 'blocks only once' do
      record << :one
      expect(barrier.wait_once).to eq :lift
      record << :two
      expect(barrier.wait_once).to eq :pass
      record << :three

      expect(record).to eq [:one, :lift, :two, :three]
    end

    context('with a local timeout') do
      let(:timeout) { delay / 4 }

      context('shorter than lift') do
        it 'unblocks on timeout' do
          record << :one
          expect(barrier.wait_once(timeout)).to eq :timeout
          record << :two
          expect(barrier.wait_once(timeout)).to eq :pass
          record << :three

          expect(record).to eq [:one, :two, :three]
        end
      end

      context('longer than lift') do
        let(:timeout) { delay * 2 }

        it 'unblocks before timeout' do
          elapsed = Datadog::Core::Utils::Time.measure do
            record << :one
            expect(barrier.wait_once(timeout)).to eq :lift
            record << :two
            expect(barrier.wait_once(timeout)).to eq :pass
            record << :three
          end

          expect(record).to eq [:one, :lift, :two, :three]

          # We should have waited strictly more than the delay time.
          expect(elapsed).to be > delay
          # But, the only wait should have been for the delay to pass,
          # i.e. the elapsed time should be only slightly greater than the
          # delay time
          expect(elapsed).to be < delay * 1.1
          # And, just to verify, this is below the timeout.
          expect(elapsed).to be < timeout
        end
      end

      context('and an instance timeout') do
        let(:instance_timeout) { delay * 2 }

        it 'prefers the local timeout' do
          record << :one
          expect(barrier.wait_once(timeout)).to eq :timeout
          record << :two
          expect(barrier.wait_once(timeout)).to eq :pass
          record << :three

          expect(record).to eq [:one, :two, :three]
        end
      end
    end

    context('with an instance timeout') do
      let(:instance_timeout) { delay / 4 }

      it 'unblocks on timeout' do
        record << :one
        expect(barrier.wait_once).to eq :timeout
        record << :two
        expect(barrier.wait_once).to eq :pass
        record << :three

        expect(record).to eq [:one, :two, :three]
      end
    end
  end
end
