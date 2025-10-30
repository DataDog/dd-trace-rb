# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/api_security/sampler'

RSpec.describe Datadog::AppSec::APISecurity::Sampler do
  let(:sampler) { described_class.new(30) }
  let(:request) { double('Rack::Request', request_method: 'GET', env: {}, script_name: '', path: '/api/users') }
  let(:response) { double('Rack::Response', status: 200) }

  describe '.thread_local' do
    before { stub_const('Datadog::AppSec::APISecurity::Sampler::THREAD_KEY', :__sampler_key__) }

    around do |example|
      Datadog.configure { |c| c.appsec.api_security.sample_delay = 30 }
      example.run
    ensure
      Datadog.configuration.reset!
      described_class.reset!
    end

    context 'when called for the first time' do
      it 'returns a new sampler instance' do
        # NOTE: Isolating the sampler in a separate thread to avoid flakiness
        thread = Thread.new do
          expect { described_class.thread_local }.to change { Thread.current.thread_variable_get(:__sampler_key__) }
            .from(nil).to(be_a(described_class))
        end

        thread.join
      end
    end

    context 'when called for the second time' do
      it 'returns the same instance' do
        expect(described_class.thread_local).to be(described_class.thread_local)
      end
    end

    context 'when called from different threads' do
      it 'returns different samplers' do
        sampler_1 = nil
        sampler_2 = nil

        Thread.new { sampler_1 = described_class.thread_local }.join
        Thread.new { sampler_2 = described_class.thread_local }.join

        expect(sampler_1).not_to be(sampler_2)
        expect(sampler_1).to be_a(described_class)
        expect(sampler_2).to be_a(described_class)
      end
    end
  end

  describe '#initialize' do
    it { expect { described_class.new(30) }.not_to raise_error }
    it { expect { described_class.new('30') }.to raise_error(ArgumentError, 'sample_delay must be an Integer') }
    it { expect { described_class.new(30.5) }.to raise_error(ArgumentError, 'sample_delay must be an Integer') }
    it { expect { described_class.new(nil) }.to raise_error(ArgumentError, 'sample_delay must be an Integer') }
  end

  describe '#sample?' do
    before { allow(Datadog::Core::Utils::Time).to receive(:now).and_return(now) }

    let(:now) { Time.new(2020, 3, 20, 13, 14, 15) }

    context 'when sample delay is zero' do
      let(:sampler) { described_class.new(0) }

      it 'always returns true' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, response)).to be(true)
      end
    end

    context 'when response status is 404' do
      let(:response) { double('Rack::Response', status: 404) }

      it 'always returns false' do
        3.times do
          expect(sampler.sample?(request, response)).to be(false)
        end
      end
    end

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

        allow(Datadog::Core::Utils::Time).to receive(:now).and_return(now + 30)

        expect(sampler.sample?(request, response)).to be(false)
      end
    end

    context 'when sampling after the delay period' do
      it 'returns true and updates the cached timestamp' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, response)).to be(false)

        allow(Datadog::Core::Utils::Time).to receive(:now).and_return(now + 31)

        expect(sampler.sample?(request, response)).to be(true)
      end
    end

    context 'with different request/response combinations' do
      let(:other_request) { double('Rack::Request', request_method: 'POST', env: {}, script_name: '', path: '/api/users') }
      let(:other_response) { double('Rack::Response', status: 201) }

      it 'treats them as separate entries' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(other_request, other_response)).to be(true)
      end
    end

    context 'with same route but different methods' do
      let(:post_request) { double('Rack::Request', request_method: 'POST', env: {}, script_name: '', path: '/api/users') }

      it 'treats them as separate entries' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(post_request, response)).to be(true)
      end
    end

    context 'with same method and route but different status' do
      let(:error_response) { double('Rack::Response', status: 500) }

      it 'treats them as separate entries' do
        expect(sampler.sample?(request, response)).to be(true)
        expect(sampler.sample?(request, error_response)).to be(true)
      end
    end
  end
end
