# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/transport/http'
require 'datadog/core/transport/http/negotiation'
require 'datadog/core/transport/negotiation'

RSpec.describe Datadog::Core::Transport::HTTP do
  before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

  describe '.root' do
    subject(:transport) { described_class.root(&client_options) }

    let(:client_options) { proc { |_client| } }

    it { is_expected.to be_a(Datadog::Core::Transport::Negotiation::Transport) }

    describe '#send_info' do
      subject(:response) { transport.send_info }

      it { is_expected.to be_a(Datadog::Core::Transport::HTTP::Negotiation::Response) }

      it { is_expected.to be_ok }
      it { is_expected.to_not have_attributes(:version => be_nil) }
      it { is_expected.to_not have_attributes(:endpoints => be_nil) }
      it { is_expected.to_not have_attributes(:config => be_nil) }
    end
  end
end
