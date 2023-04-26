# frozen_string_literal: true

require 'rspec'
require 'lib/datadog/tracing/contrib/aws/services/s3'

RSpec.describe 'add_s3_tags' do
  let(:span) { instance_double('Span') }
  let(:params) { {} }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with bucket name provided' do
    let(:params) { { bucket: 'my-bucket-name' } }

    it 'sets the bucket_name based on the provided bucket name' do
      add_s3_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_BUCKET_NAME, 'my-bucket-name')
    end
  end

  context 'with no bucket name provided' do
    it 'sets the bucket_name to nil' do
      add_s3_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_BUCKET_NAME, nil)
    end
  end
end
