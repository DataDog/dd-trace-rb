require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Options) }

  describe '#options' do
    subject(:options) { settings.options }
    it { is_expected.to include(:service_name) }
    it { is_expected.to include(:tracer) }
  end

  describe 'when setting :service_name' do
    shared_examples_for 'prefixed name' do
      let(:original_service_name) { 'bar' }
      let(:tracer) { instance_double(Datadog::Tracer, service_prefix: service_prefix) }

      before(:each) { settings.set_option(:tracer, tracer) }

      describe 'via #set_option' do
        subject(:service_name) { settings.set_option(:service_name, original_service_name) }
        it do
          expect { service_name }.to change { settings.service_name }
            .from(nil)
            .to("#{service_prefix}#{original_service_name}")
        end
      end

      describe 'via #[]=' do
        subject(:service_name) { settings[:service_name] = original_service_name }
        it do
          expect { service_name }.to change { settings.service_name }
            .from(nil)
            .to("#{service_prefix}#{original_service_name}")
        end
      end

      describe 'via #service_name' do
        subject(:service_name) { settings.service_name = original_service_name }
        it do
          expect { service_name }.to change { settings.service_name }
            .from(nil)
            .to("#{service_prefix}#{original_service_name}")
        end
      end
    end

    context 'without a :service_prefix on the Tracer' do
      it_behaves_like 'prefixed name' do
        let(:service_prefix) { nil }
      end
    end

    context 'with :service_prefix on the Tracer' do
      it_behaves_like 'prefixed name' do
        let(:service_prefix) { 'foo_' }
      end
    end
  end
end
