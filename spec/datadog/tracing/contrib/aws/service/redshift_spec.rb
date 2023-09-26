# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/redshift'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Redshift do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:redshift) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'when cluster_identifier is present' do
    let(:cluster_identifier) { 'myID' }
    let(:params) { { cluster_identifier: cluster_identifier } }

    it 'sets clusteridentifier tag' do
      cloud_watch_logs.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_CLUSTER_IDENTIFIER, cluster_identifier)
    end
  end
end
