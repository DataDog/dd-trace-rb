require 'spec_helper'

RSpec.describe 'Basic scenarios' do
  include_context 'integration test'

  context 'default' do
    subject { get('basic/default') }
    it { is_expected.to be_a_kind_of(Net::HTTPOK) }
  end

  context 'profiling health' do
    subject { get('health/profiling') }
    it { is_expected.to be_a_kind_of(Net::HTTPOK), "Got #{subject.inspect} with body: '#{subject.body}'" }
  end
end
