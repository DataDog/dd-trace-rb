require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Extensions do
  shared_context 'registry with integration' do
    let(:registry) { {} }
    let(:integration_name) { :example }
    let(:integration_options) { double('integration integration_options') }
    let(:integration_class) { double('integration class', loaded?: false) }
    let(:integration) do
      instance_double(
        Datadog::AppSec::Contrib::Integration::RegisteredIntegration,
        klass: integration_class,
        options: integration_options
      )
    end

    before do
      registry[integration_name] = integration

      allow(Datadog::AppSec::Contrib::Integration).to receive(:registry).and_return(registry)
    end
  end

  context 'for' do
    describe Datadog do
      after { described_class.configuration.appsec.send(:reset!) }
      describe '#configure' do
        include_context 'registry with integration'

        context 'given a block' do
          subject(:configure) { described_class.configure(&block) }

          context 'that calls #instrument for an integration' do
            let(:block) { proc { |c| c.appsec.instrument integration_name } }

            it 'configures the integration' do
              # If integration_class.loaded? is invoked, it means the correct integration is being activated.
              begin
                old_appsec_enabled = ENV['DD_APPSEC_ENABLED']
                ENV['DD_APPSEC_ENABLED'] = 'true'
                expect(integration_class).to receive(:loaded?).and_return(false)

                configure
              ensure
                ENV['DD_APPSEC_ENABLED'] = old_appsec_enabled
              end
            end
          end
        end
      end
    end

    describe Datadog::Core::Configuration::Settings do
      include_context 'registry with integration'

      subject(:settings) { described_class.new.appsec }

      after { settings.send(:reset!) }

      describe '#enabled' do
        subject(:enabled) { settings.enabled }
        it { is_expected.to eq(true) }
      end

      describe '#enabled=' do
        subject(:enabled_) { settings.enabled = false }
        it { expect { enabled_ }.to change { settings.enabled }.from(true).to(false) }
      end

      describe '#ruleset' do
        subject(:ruleset) { settings.ruleset }
        it { is_expected.to eq(:recommended) }
      end

      describe '#ruleset=' do
        subject(:ruleset_) { settings.ruleset = :strict }
        it { expect { ruleset_ }.to change { settings.ruleset }.from(:recommended).to(:strict) }
      end

      describe '#waf_timeout' do
        subject(:waf_timeout) { settings.waf_timeout }
        it { is_expected.to eq(5000) }
      end

      describe '#waf_timeout=' do
        subject(:waf_timeout_) { settings.waf_timeout = 3 }
        it { expect { waf_timeout_ }.to change { settings.waf_timeout }.from(5000).to(3) }
      end

      describe '#waf_debug' do
        subject(:waf_debug) { settings.waf_debug }
        it { is_expected.to eq(false) }
      end

      describe '#waf_debug=' do
        subject(:waf_debug_) { settings.waf_debug = true }
        it { expect { waf_debug_ }.to change { settings.waf_debug }.from(false).to(true) }
      end

      describe '#trace_rate_limit' do
        subject(:trace_rate_limit) { settings.trace_rate_limit }
        it { is_expected.to eq(100) }
      end

      describe '#trace_rate_limit=' do
        subject(:trace_rate_limit_) { settings.trace_rate_limit = 2 }
        it { expect { trace_rate_limit_ }.to change { settings.trace_rate_limit }.from(100).to(2) }
      end

      describe '#ip_denylist' do
        subject(:ip_denylist) { settings.ip_denylist }
        it { is_expected.to eq([]) }
      end

      describe '#ip_denylist=' do
        subject(:ip_denylist_) { settings.ip_denylist = ['192.192.1.1'] }
        it { expect { ip_denylist_ }.to change { settings.ip_denylist }.from([]).to(['192.192.1.1']) }
      end

      describe '#user_id_denylist' do
        subject(:user_id_denylist) { settings.user_id_denylist }
        it { is_expected.to eq([]) }
      end

      describe '#user_id_denylist=' do
        subject(:user_id_denylist_) { settings.user_id_denylist = ['24528736564812'] }
        it { expect { user_id_denylist_ }.to change { settings.user_id_denylist }.from([]).to(['24528736564812']) }
      end

      describe '#[]' do
        describe 'when the integration exists' do
          subject(:get) { settings[integration_name] }

          let(:integration_options) { { foo: :bar } }

          before { settings.instrument(integration_name, integration_options) }

          it 'retrieves the described configuration' do
            is_expected.to eq(integration_options)
          end
        end

        context 'when the integration doesn\'t exist' do
          it do
            expect { settings[:foobar] }.to raise_error(ArgumentError, /foobar/)
          end
        end
      end
    end
  end
end
