# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/cloudwatchlogs'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::CloudWatchLogs do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:cloud_watch_logs) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'when log_group_name is present' do
    let(:log_group_name) { 'foobar' }
    let(:params) { { log_group_name: log_group_name } }

    it 'sets loggroupname tag' do
      cloud_watch_logs.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_LOG_GROUP_NAME, 'foobar')
    end
  end
end
