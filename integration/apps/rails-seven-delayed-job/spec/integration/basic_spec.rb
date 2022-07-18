require 'spec_helper'
require 'json'

RSpec.describe 'Basic scenarios' do
  include_context 'integration test'

  context 'default' do
    subject { get('basic/default') }
    it { is_expected.to be_a_kind_of(Net::HTTPOK) }
  end

  context 'component checks' do
    subject { post('jobs') }

    it { is_expected.to be_a_kind_of(Net::HTTPOK) }
  end
end
