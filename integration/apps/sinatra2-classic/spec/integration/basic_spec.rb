require 'spec_helper'
require 'rspec/wait'
require 'securerandom'
require 'json'

RSpec.describe 'Basic scenarios' do
  include_context 'integration test'

  context 'default' do
    subject { get('basic/default') }
    it { is_expected.to be_a_kind_of(Net::HTTPOK) }
  end

  let(:expected_profiler_available) { true }

  let(:expected_profiler_threads) do
    expected_profiler_available ? contain_exactly(
      'Datadog::Profiling::Collectors::IdleSamplingHelper',
      'Datadog::Profiling::Collectors::CpuAndWallTimeWorker',
      'Datadog::Profiling::Scheduler',
    ) : eq(nil).or(eq([]))
  end

  context 'component checks' do
    subject { get('health/detailed') }

    let(:json_result) { JSON.parse(subject.body, symbolize_names: true) }

    it { is_expected.to be_a_kind_of(Net::HTTPOK) }

    it 'should be profiling' do
      expect(json_result).to include(
        profiler_available: expected_profiler_available,
        profiler_threads: expected_profiler_threads,
      )
    end

    it 'webserver sanity checking' do
      puts "      Webserver: #{json_result.fetch(:webserver_process)}"
    end
  end
end
