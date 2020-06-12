require 'ddtrace/contrib/support/spec_helper'

require 'faraday'
require 'ddtrace'
require 'ddtrace/contrib/faraday/patcher'

RSpec.describe 'Faraday instrumentation' do
  include_context 'tracer logging'

  let(:configuration_options) { {} }

  # Enable the test tracer
  before(:each) do
    Datadog.configure do |c|
      c.use :faraday, configuration_options
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
      /.*Use of Datadog::Pin with Faraday is DEPRECATED.*/
    ]
  end

  it 'does not generate deprecation warnings' do
    expect(log_buffer).to_not contain_line_with(*deprecation_warnings)
  end

  context 'when pin is referenced by' do
    describe 'Datadog::Pin.get_from' do
      subject(:pin) { Datadog::Pin.get_from(Faraday) }
      before(:each) { pin }
      after(:each) { reset_deprecation_warnings!(pin) }

      it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }

      context 'twice' do
        before(:each) { Datadog::Pin.get_from(Faraday) }
        it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
      end

      context 'and then calls' do
        # Make sure 'service_name' passes through to underlying configuration
        describe '#service_name=' do
          let(:original_service_name) { Datadog.configuration[:faraday][:service_name] }
          let(:new_service_name) { 'new_service' }
          after(:each) { pin.service_name = original_service_name }

          it 'updates the configuration service name' do
            expect { pin.service_name = new_service_name }
              .to change { Datadog.configuration[:faraday][:service_name] }
              .from(original_service_name).to(new_service_name)
          end
        end
      end
    end

    describe '#datadog_pin' do
      subject(:pin) { Faraday.datadog_pin }
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
        Faraday.datadog_pin = new_pin
      end
      let(:original_pin) do
        # We know this to create deprecation warnings...
        # Retrieve the pin and reset the buffer
        Faraday.datadog_pin.tap do
          log_buffer.truncate(0)
          log_buffer.rewind
        end
      end
      let(:new_pin) { Datadog::Pin.new('new_service') }

      after(:each) do
        # Restore original pin
        Faraday.datadog_pin = original_pin
        reset_deprecation_warnings!(original_pin)
      end

      it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
    end
  end
end
