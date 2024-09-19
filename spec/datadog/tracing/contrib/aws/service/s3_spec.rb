# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/s3'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::S3 do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:s3) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with bucket name provided' do
    let(:params) { { bucket: 'my-bucket-name' } }

    it 'sets the bucket_name based on the provided bucket name' do
      s3.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_BUCKET_NAME, 'my-bucket-name')
    end
  end

  context 'with no bucket name provided' do
    it 'sets the bucket_name to nil' do
      s3.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_BUCKET_NAME, nil)
    end
  end
end
