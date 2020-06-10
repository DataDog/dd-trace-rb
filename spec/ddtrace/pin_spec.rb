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
      let(:options) do
        {
          app: double('app'),
          app_type: double('app_type'),
          config: double('config'),
          name: double('name'),
          tags: double('tags'),
          writer: double('writer')
        }
      end

      it do
        is_expected.to have_attributes(
          app: options[:app],
          app_type: options[:app_type],
          config: options[:config],
          name: nil,
          service_name: service_name,
          tags: options[:tags],
          writer: nil
        )
      end
    end
  end

  describe '#tracer' do
    subject(:tracer) { pin.tracer }

    context 'when a tracer has been provided' do
      let(:options) { super().merge(tracer: tracer_option) }
      let(:tracer_option) { get_test_tracer }

      before do
        allow_any_instance_of(Datadog::Pin).to receive(:deprecation_warning).and_call_original
      end

      it 'expect a deprecation warning' do
        expect(Datadog.logger).to receive(:warn).with(include('DEPRECATED'))
        subject
      end
    end

    context 'when no tracer has been provided' do
      it { is_expected.to be Datadog.tracer }

      context 'and the default tracer mutates' do
        let(:new_tracer) { get_test_tracer }

        it 'gets the current tracer' do
          old_tracer = Datadog.tracer

          expect { allow(Datadog).to receive(:tracer).and_return(new_tracer) }
            .to change { pin.tracer }
            .from(old_tracer)
            .to(new_tracer)
        end
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
