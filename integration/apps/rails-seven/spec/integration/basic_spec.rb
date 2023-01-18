require 'spec_helper'
require 'json'

RSpec.describe 'Basic scenarios' do
  include_context 'integration test'

  context 'default' do
    subject { get('basic/default') }
    it { is_expected.to be_a_kind_of(Net::HTTPOK) }
  end

  context 'component checks' do
    subject { get('health/detailed') }

    let(:json_result) { JSON.parse(subject.body, symbolize_names: true) }

    it { is_expected.to be_a_kind_of(Net::HTTPOK) }

    it 'should be profiling' do
      expect(json_result).to include(
        profiler_available: true,
        profiler_threads: contain_exactly('Datadog::Profiling::Collectors::OldStack', 'Datadog::Profiling::Scheduler')
      )
    end

    it 'should be sending telemetry events' do
      expect(json_result).to include(
        telemetry_enabled: true,
        telemetry_client_enabled: true,
        telemetry_worker_enabled: true
      )
    end

    it 'webserver sanity checking' do
      puts "      Webserver: #{json_result.fetch(:webserver_process)}"
    end
  end

  context 'default' do
    subject { `bin/rails runner 'print "OK"'` }
    it { expect { subject }.to output('OK').to_stdout }
  end
end
