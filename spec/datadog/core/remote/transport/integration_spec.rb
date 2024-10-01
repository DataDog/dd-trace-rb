# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/utils/base64'
require 'datadog/core/remote/transport/http'
require 'datadog/core/remote/transport/http/negotiation'
require 'datadog/core/remote/transport/negotiation'

RSpec.describe Datadog::Core::Remote::Transport::HTTP do
  skip_unless_integration_testing_enabled

  describe '.root' do
    subject(:transport) { described_class.root(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Core::Remote::Transport::Negotiation::Transport) }

    describe '#send_info' do
      subject(:response) { transport.send_info }

      it { is_expected.to be_a(Datadog::Core::Remote::Transport::HTTP::Negotiation::Response) }

      it { is_expected.to be_ok }
      it { is_expected.to_not have_attributes(:version => be_nil) }
      it { is_expected.to_not have_attributes(:endpoints => be_nil) }
      it { is_expected.to_not have_attributes(:config => be_nil) }
    end
  end

  describe '.v7' do
    before { skip 'TODO: needs remote config on api key+agent+backend' if ENV['TEST_DATADOG_INTEGRATION'] }

    subject(:transport) { described_class.v7(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Core::Remote::Transport::Config::Transport) }

    describe '#send_config' do
      let(:state) do
        OpenStruct.new(
          {
            root_version: 1,              # unverified mode, so 1
            targets_version: 0,           # from scratch, so zero
            config_states: [],            # from scratch, so empty
            has_error: false,             # from scratch, so false
            error: '',                    # from scratch, so blank
            opaque_backend_state: '',     # from scratch, so blank
          }
        )
      end

      let(:id) { SecureRandom.uuid }

      let(:products) { [] }

      let(:capabilities) { 0 }

      let(:capabilities_binary) do
        capabilities
          .to_s(16)
          .tap { |s| s.size.odd? && s.prepend('0') }
          .scan(/\h\h/)
          .map { |e| e.to_i(16) }
          .pack('C*')
      end

      let(:payload) do
        {
          client: {
            state: {
              root_version: state.root_version,
              targets_version: state.targets_version,
              config_states: state.config_states,
              has_error: state.has_error,
              error: state.error,
              backend_client_state: state.opaque_backend_state,
            },
            id: id,
            products: products,
            is_tracer: true,
            is_agent: false,
            client_tracer: {
              runtime_id: Datadog::Core::Environment::Identity.id,
              language: Datadog::Core::Environment::Identity.lang,
              tracer_version: Datadog::Core::Environment::Identity.gem_datadog_version,
              service: Datadog.configuration.service,
              env: Datadog.configuration.env,
              tags: [],
            },
            capabilities: Datadog::Core::Utils::Base64.encode64(capabilities_binary).chomp,
          },
          cached_target_files: [],
        }
      end

      subject(:response) { transport.send_config(payload) }

      it { is_expected.to be_a(Datadog::Core::Remote::Transport::HTTP::Config::Response) }

      it { is_expected.to be_ok }
      it { is_expected.to_not have_attributes(:roots => be_nil) }
      it { is_expected.to_not have_attributes(:targets => be_nil) }
    end
  end
end
