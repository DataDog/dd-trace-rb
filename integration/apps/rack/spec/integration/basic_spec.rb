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

  let(:expected_profiler_threads) do
    # NOTE: Threads can't be named on Ruby 2.1 and 2.2
    contain_exactly('Datadog::Profiling::Collectors::OldStack', 'Datadog::Profiling::Scheduler') unless RUBY_VERSION < '2.3'
  end

  context 'component checks' do
    subject { get('health/detailed') }

    let(:json_result) { JSON.parse(subject.body, symbolize_names: true) }

    it { is_expected.to be_a_kind_of(Net::HTTPOK) }

    it 'should be profiling' do
      expect(json_result).to include(
        profiler_available: true,
        profiler_threads: expected_profiler_threads,
      )
    end

    it 'webserver sanity checking' do
      puts "      Webserver: #{json_result.fetch(:webserver_process)}"
    end
  end

  context 'resque usage' do
    let(:key) { SecureRandom.uuid }

    before do
      post('background_jobs/write_resque', key: key, value: 'it works!')
    end

    it 'runs a test task, with profiling enabled' do
      body = nil
      wait_for { body = get("background_jobs/read_resque?key=#{key}").body.to_s }.to include('it works!')

      expect(JSON.parse(body, symbolize_names: true)).to include(
        key: key,
        resque_process: match(/resque/),
        profiler_available: true,
        profiler_threads: expected_profiler_threads,
      )
    end
  end

  context 'sidekiq usage' do
    let(:key) { SecureRandom.uuid }

    before do
      post('background_jobs/write_sidekiq', key: key, value: 'it works!')
    end

    it 'runs a test task, with profiling enabled' do
      body = nil
      wait_for { body = get("background_jobs/read_sidekiq?key=#{key}").body.to_s }.to include('it works!')

      expect(JSON.parse(body, symbolize_names: true)).to include(
        key: key,
        sidekiq_process: match(/sidekiq/),
        profiler_available: true,
        profiler_threads: expected_profiler_threads,
      )
    end
  end
end
