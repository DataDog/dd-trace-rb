require 'spec_helper'
require 'rspec/wait'
require 'securerandom'
require 'json'

RSpec.describe 'Trace stress tests' do
  include_context 'integration test'

  before { skip('Stress tests do not run automatically.') unless ENV['TEST_STRESS'] }

  let(:iterations) { 100_000 }

  context 'default route' do
    it 'successfully performs requests without errors' do
      iterations.times do
        response = get('basic/default')
        expect(response).to be_a_kind_of(Net::HTTPOK)
      end
    end
  end
end
