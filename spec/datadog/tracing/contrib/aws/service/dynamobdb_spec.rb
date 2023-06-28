# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/dynamodb'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::DynamoDB do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:dynamodb) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with table_name provided' do
    let(:table_name) { 'example-table' }
    let(:params) { { table_name: table_name } }

    it 'sets the table_name tag' do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, table_name)
    end
  end

  context 'with no table_name provided' do
    it 'does not set the table_name tag' do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, nil)
    end
  end
end
