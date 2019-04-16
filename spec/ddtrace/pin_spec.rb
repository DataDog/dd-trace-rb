require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Pin do
  subject(:pin) { described_class.new(service_name, options) }

  let(:service_name) { 'test-service' }
  let(:options) { {} }
  let(:target) { Object.new }

  describe '#initialize' do
    before(:each) { pin }

    context 'when given some options' do
      let(:options) { { app: 'anapp' } }

      it do
        expect(pin.service).to eq(service_name)
        expect(pin.app).to eq(options[:app])
      end
    end

    context 'when given sufficient info' do
      let(:options) { { app: 'test-app', app_type: 'test-type', tracer: tracer } }
      let(:tracer) { get_test_tracer }
    end

    context 'when given insufficient info' do
      let(:options) { { app_type: 'test-type', tracer: tracer } }
      let(:tracer) { get_test_tracer }

      it 'does not sets the service info' do
        expect(tracer.services).to be_empty
      end
    end
  end

  describe '#onto' do
    let(:options) { { app: 'anapp' } }
    let(:returned_pin) { described_class.get_from(target) }

    before(:each) { pin.onto(target) }

    it 'attaches the pin to the target' do
      expect(returned_pin.service).to eq(service_name)
      expect(returned_pin.app).to eq(options[:app])
    end
  end

  describe '#get_from' do
    subject(:returned_pin) { described_class.get_from(target) }

    context 'called against' do
      context '0' do
        let(:target) { 0 }
        it { is_expected.to be nil }
      end

      context 'nil' do
        let(:target) { nil }
        it { is_expected.to be nil }
      end

      context 'self' do
        let(:target) { self }
        it { is_expected.to be nil }
      end
    end

    context 'when a custom pin has already been defined' do
      let(:target_class) do
        Class.new do
          def datadog_pin
            @custom_attribute
          end

          def datadog_pin=(pin)
            @custom_attribute = 'The PIN is set!'
          end
        end
      end

      let(:target) { target_class.new }
      before(:each) { pin.onto(target) }

      it 'returns the custom pin' do
        is_expected.to eq('The PIN is set!')
      end
    end
  end

  describe '#to_s' do
    subject(:string) { pin.to_s }
    let(:service_name) { 'abc' }
    let(:options) { { app: 'anapp', app_type: 'db' } }
    it { is_expected.to eq('Pin(service:abc,app:anapp,app_type:db,name:)') }
  end

  describe '#datadog_pin' do
    let(:returned_pin) { target.datadog_pin }
    before(:each) { pin.onto(target) }
    it { expect(returned_pin.service).to eq(service_name) }
  end

  describe '#enabled?' do
    subject(:enabled) { pin.enabled? }
    it { is_expected.to be true }

    context 'when the tracer is disabled' do
      let(:options) { { tracer: Datadog::Tracer.new(writer: FauxWriter.new) } }
      before(:each) { pin.tracer.enabled = false }
      it { is_expected.to be false }
    end
  end
end

RSpec.describe Datadog::DeprecatedPin do
  include_context 'tracer logging'

  subject(:pin) { pin_class.new(service_name) }
  let(:pin_class) { Class.new(Datadog::Pin) { include Datadog::DeprecatedPin } }
  let(:service_name) { 'my_service' }

  describe '#onto' do
    before(:each) { pin.onto(object) }
    let(:object) { Object.new }

    let(:deprecation_warnings) do
      [
        /.*#datadog_pin.*/,
        /.*Use of Datadog::Pin is DEPRECATED.*/
      ]
    end

    it 'does not generate deprecation warnings' do
      expect(log_buffer.length).to eq(0)
      expect(log_buffer).to_not contain_line_with(*deprecation_warnings)
      expect(log_buffer).to_not contain_line_with(*deprecation_warnings)
    end

    context 'when invoked then followed by' do
      describe 'Datadog::Pin.get_from' do
        before(:each) { Datadog::Pin.get_from(object) }
        it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }

        context 'twice' do
          it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
        end
      end

      describe '#datadog_pin' do
        before(:each) { object.datadog_pin }
        it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }

        context 'twice' do
          it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
        end
      end

      describe '#datadog_pin=' do
        before(:each) { object.datadog_pin = new_pin }
        let(:new_pin) { Datadog::Pin.new('new_service') }
        it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }

        context 'twice' do
          it { expect(log_buffer).to contain_line_with(*deprecation_warnings).once }
        end
      end
    end
  end
end
