require 'spec_helper'
require 'json'

RSpec.describe 'Basic scenarios' do
  include_context 'integration test'

  context 'component checks' do
    subject { get('health/detailed') }

    let(:json_result) { JSON.parse(subject.body, symbolize_names: true) }

    it { is_expected.to be_a_kind_of(Net::HTTPOK) }

    it 'webserver sanity checking' do
      puts "      Webserver: #{json_result.fetch(:webserver_process)}"
    end
  end

  context 'job checks' do
    subject { post('jobs') }

    it { is_expected.to be_a_kind_of(Net::HTTPOK) }
  end
end
