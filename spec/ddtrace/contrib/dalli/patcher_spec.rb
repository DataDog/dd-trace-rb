require 'spec_helper'

require 'dalli'
require 'ddtrace'
require 'ddtrace/contrib/dalli/patcher'

RSpec.describe 'Dalli instrumentation' do
  include_context 'tracer logging'

  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  # Enable the test tracer
  before(:each) do
    Datadog.configure do |c|
      c.use :dalli, configuration_options
    end
  end

  def reset_deprecation_warnings!(pin)
    if pin.instance_variable_defined?(:@done_once)
      pin.instance_variable_get(:@done_once).delete('#datadog_pin')
      pin.instance_variable_get(:@done_once).delete('#datadog_pin=')
    end
  end

  let(:deprecation_warnings) do
    [
      /.*#datadog_pin.*/,
      /.*Use of Datadog::Pin with Dalli is DEPRECATED.*/
    ]
  end

  it 'does not generate deprecation warnings' do
    expect(log_buffer).to_not contain_line_with(*deprecation_warnings)
  end

  context 'when pin is referenced by' do
    describe 'Datadog::Pin.get_from' do
      subject(:pin) { Datadog::Pin.get_from(Dalli) }
      before(:each) { pin }
      after(:each) { reset_deprecation_warnings!(pin) }

      it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }

      context 'twice' do
        before(:each) { Datadog::Pin.get_from(Dalli) }
        it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
      end

      context 'and then calls' do
        # Make sure 'service_name' passes through to underlying configuration
        describe '#service_name=' do
          before(:each) do
            original_service_name
            pin.service_name = service_name
          end
          let(:original_service_name) { Datadog.configuration[:dalli][:service_name] }
          let(:service_name) { 'new_service' }
          after(:each) { pin.service_name = original_service_name }
          it { expect(Datadog.configuration[:dalli][:service_name]).to eq(service_name) }
        end

        # Make sure 'tracer' passes through to underlying configuration
        describe 'tracer=' do
          before(:each) { pin.tracer = new_tracer }
          let(:new_tracer) { double('tracer') }
          it { expect(Datadog.configuration[:dalli][:tracer]).to eq(new_tracer) }
        end
      end
    end

    describe '#datadog_pin' do
      subject(:pin) { Dalli.datadog_pin }
      before(:each) { pin }
      after(:each) { reset_deprecation_warnings!(pin) }
      it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }

      context 'twice' do
        it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
      end
    end

    describe '#datadog_pin=' do
      before(:each) do
        # Store original pin first
        original_pin

        # Set new pin
        Dalli.datadog_pin = new_pin
      end
      let(:original_pin) do
        # We know this to create deprecation warnings...
        # Retrieve the pin and reset the buffer
        Dalli.datadog_pin.tap do
          log_buffer.truncate(0)
          log_buffer.rewind
        end
      end
      let(:new_pin) { Datadog::Pin.new('new_service') }

      after(:each) do
        # Restore original pin
        Dalli.datadog_pin = original_pin
        reset_deprecation_warnings!(original_pin)
      end

      it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
    end
  end
end
