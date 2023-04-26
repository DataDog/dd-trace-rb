# frozen_string_literal: true

require 'rspec'
require 'lib/datadog/tracing/contrib/aws/services/dynamodb'

RSpec.describe 'add_dynamodb_tags' do
  let(:span) { instance_double('Span') }
  let(:params) { {} }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with table_name provided' do
    let(:table_name) { 'example-table' }
    let(:params) { { table_name: table_name } }

    it 'sets the table_name tag' do
      add_dynamodb_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, table_name)
    end
  end

  context 'with no table_name provided' do
    it 'does not set the table_name tag' do
      add_dynamodb_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, nil)
    end
  end
end
