require 'spec_helper'
require 'rspec/wait'
require 'securerandom'

RSpec.describe 'Basic scenarios' do
  include_context 'integration test'

  context 'default' do
    subject { get('basic/default') }
    it do
      is_expected.to be_a_kind_of(Net::HTTPOK)
      puts "    #{subject.body.each_line.to_a.last}" # Print last line of request (webserver info) for sanity checking
    end
  end

  context 'profiling health' do
    subject { get('health/profiling') }
    it { is_expected.to be_a_kind_of(Net::HTTPOK), "Got #{subject.inspect} with body: '#{subject.body}'" }
  end

  context 'sidekiq usage' do
    let(:key) { SecureRandom.uuid }

    before do
      post('background_jobs/write_sidekiq', key: key, value: 'it works!')
    end

    it 'runs a simple task successfully' do
      wait_for { get("background_jobs/read_sidekiq?key=#{key}").body }.to include('it works!')
    end
  end
end
