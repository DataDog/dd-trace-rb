require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/ext/integration'

require 'cucumber'
require 'ddtrace'

RSpec.describe 'Cucumber events' do
  let(:configuration_options) { {} }

  before(:each) do
    Datadog.configure do |c|
      c.use :cucumber, configuration_options
    end
  end

  context 'pin' do
    subject(:pin) { Datadog::Pin.get_from(Cucumber) }

    it 'has the correct attributes' do
      # expect(pin.service).to eq(service_name)
      expect(pin.app_type).to eq(Datadog::Ext::AppTypes::TEST)
    end
  end
end
