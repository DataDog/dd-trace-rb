# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/api_security/sampler'

RSpec.describe Datadog::AppSec::APISecurity::Sampler do
  let(:sampler) { described_class.new(30) }
  let(:request) { double('request', method: 'GET', route_path: '/api/users') }
  let(:response) { double('response', status: 200) }

  describe '.thread_local' do
    after { described_class.deactivate }

    it { expect(described_class.thread_local).to be_nil }

    it 'returns the activated sampler' do
      described_class.activate(sampler)
      expect(described_class.thread_local).to be(sampler)
    end
  end

  describe '.activate' do
    after { described_class.deactivate }

    it 'sets the thread-local sampler' do
      expect { described_class.activate(sampler) }
        .to change { described_class.thread_local }.from(nil).to(sampler)
    end
  end

  describe '.deactivate' do
    before { described_class.activate(sampler) }
    after { described_class.deactivate }

    it 'clears the thread-local sampler' do
      expect { described_class.deactivate }
        .to change { described_class.thread_local }.from(sampler).to(nil)
    end
  end

  describe '#initialize' do
    it { expect { described_class.new(30) }.not_to raise_error }
    it { expect { described_class.new('30') }.to raise_error(ArgumentError, 'sample_delay must be an Integer') }
    it { expect { described_class.new(30.5) }.to raise_error(ArgumentError, 'sample_delay must be an Integer') }
    it { expect { described_class.new(nil) }.to raise_error(ArgumentError, 'sample_delay must be an Integer') }
  end

  describe '#sample?' do
    before { allow(Time).to receive(:now).and_return(now) }

    let(:now) { Time.new(2020, 3, 20, 13, 14, 15) }

    context 'when sampling for the first time' do
      it { expect(sampler.sample?(request, response)).to be(true) }
    end

    context 'when sampling twice within the delay period' do
      it 'returns false for the second call' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, response)).to be(false)
      end
    end

    context 'when sampling exactly at the delay boundary' do
      it 'returns false and does not update the cached timestamp' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, response)).to be(false)

        allow(Time).to receive(:now).and_return(now + 30)

        expect(sampler.sample?(request, response)).to be(false)
      end
    end

    context 'when sampling after the delay period' do
      it 'returns true and updates the cached timestamp' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, response)).to be(false)

        allow(Time).to receive(:now).and_return(now + 31)

        expect(sampler.sample?(request, response)).to be(true)
      end
    end

    context 'with different request/response combinations' do
      let(:other_request) { double('request', method: 'POST', route_path: '/api/users') }
      let(:other_response) { double('response', status: 201) }

      it 'treats them as separate entries' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(other_request, other_response)).to be(true)
      end
    end

    context 'with same route but different methods' do
      let(:post_request) { double('request', method: 'POST', route_path: '/api/users') }

      it 'treats them as separate entries' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(post_request, response)).to be(true)
      end
    end

    context 'with same method and route but different status' do
      let(:error_response) { double('response', status: 500) }

      it 'treats them as separate entries' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, error_response)).to be(true)
      end
    end
  end
end
