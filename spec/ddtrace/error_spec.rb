require 'spec_helper'

require 'ddtrace/error'

RSpec.describe Datadog::Error do
  describe '::build_from' do
    subject(:build_from) { described_class.build_from(value) }

    context "given #{described_class}" do
      let(:value) { described_class.new }
      it { is_expected.to be value }
    end

    context 'given an Array' do
      let(:value) { [type, message, backtrace] }
      let(:type) { 'ZeroDivisionError' }
      let(:message) { 'divided by 0' }
      let(:backtrace) { ['line 1', 'line 2'] }

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(build_from.type).to eq(type)
        expect(build_from.message).to eq(message)
        expect(build_from.backtrace).to eq("line 1\nline 2")
      end
    end

    # rubocop:disable Lint/RaiseException
    # rubocop:disable Lint/RescueException
    context 'given an Exception' do
      let(:value) do
        begin
          # Raise and catch this to generate a backtrace
          raise Exception, 'divided by 0'
        rescue Exception => e
          e
        end
      end

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(build_from.type).to eq('Exception')
        expect(build_from.message).to eq('divided by 0')
        expect(build_from.backtrace).to match(/.*error_spec.rb.*/)
      end
    end
    # rubocop:enable Lint/RaiseException
    # rubocop:enable Lint/RescueException

    # rubocop:disable RSpec/VerifiedDoubles
    context 'given an object that responds to message' do
      let(:value) { double('custom object', message: message) }
      let(:message) { 'divided by 0' }

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(build_from.type).to eq(value.class.to_s)
        expect(build_from.message).to eq(message)
        expect(build_from.backtrace).to eq('')
      end
    end

    context 'given an unknown object' do
      let(:value) { double('custom object') }
      it { is_expected.to be described_class::BlankError }
    end
    # rubocop:enable RSpec/VerifiedDoubles
  end

  describe '::new' do
    before do
      allow(Datadog::Utils).to receive(:utf8_encode)
        .and_call_original
    end

    context 'given nothing' do
      subject(:error) { described_class.new }

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(error.type).to eq('')
        expect(error.message).to eq('')
        expect(error.backtrace).to eq('')
      end
    end

    context 'given a type' do
      subject(:error) { described_class.new(type) }
      let(:type) { 'ZeroDivisionError' }

      before do
        expect(Datadog::Utils).to receive(:utf8_encode)
          .with(type)
          .and_call_original
      end

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(error.type).to eq(type)
        expect(error.message).to eq('')
        expect(error.backtrace).to eq('')
      end
    end

    context 'given a type and message' do
      subject(:error) { described_class.new(type, message) }
      let(:type) { 'ZeroDivisionError' }
      let(:message) { 'divided by 0' }

      before do
        expect(Datadog::Utils).to receive(:utf8_encode)
          .with(type)
          .and_call_original

        expect(Datadog::Utils).to receive(:utf8_encode)
          .with(message)
          .and_call_original
      end

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(error.type).to eq(type)
        expect(error.message).to eq(message)
        expect(error.backtrace).to eq('')
      end
    end

    context 'given a type, message and backtrace' do
      subject(:error) { described_class.new(type, message, backtrace) }

      let(:type) { 'ZeroDivisionError' }
      let(:message) { 'divided by 0' }
      let(:backtrace) { ['line 1', 'line 2'] }

      before do
        expect(Datadog::Utils).to receive(:utf8_encode)
          .with(type)
          .and_call_original

        expect(Datadog::Utils).to receive(:utf8_encode)
          .with(message)
          .and_call_original

        expect(Datadog::Utils).to receive(:utf8_encode)
          .with("line 1\nline 2")
          .and_call_original
      end

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(error.type).to eq(type)
        expect(error.message).to eq(message)
        expect(error.backtrace).to eq("line 1\nline 2")
      end
    end
  end
end
