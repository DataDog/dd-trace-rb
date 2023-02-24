require 'datadog/tracing/contrib/support/spec_helper'

require 'aws-sdk'
require 'datadog/tracing/contrib/aws/parsed_context'

RSpec.describe Datadog::Tracing::Contrib::Aws::ParsedContext do
  subject(:parsed_context) { described_class.new(context) }

  let(:context) { client.list_buckets.context }

  let(:client) { ::Aws::S3::Client.new(region: 'us-west-2', stub_responses: responses) }
  let(:responses) { true }

  describe '#new' do
    context 'given a context with typical values' do
      it do
        is_expected.to have_attributes(
          resource: 's3.list_buckets',
          operation: :list_buckets,
          status_code: 200,
          http_method: 'GET',
          region: 'us-west-2',
          retry_attempts: 0,
          path: '/'
        )
      end

      it { expect(parsed_context.host).to include('us-west-2.amazonaws.com') }
    end
  end

  describe '#safely' do
    subject(:attribute) { parsed_context.safely(attribute_name, fallback) }

    let(:attribute_name) { :resource }
    let(:fallback) { 'fallback_name' }

    context 'when the attribute raises an error' do
      before { allow(parsed_context).to receive(attribute_name).and_raise('Parse error.') }

      it { is_expected.to eq(fallback) }
    end
  end
end
