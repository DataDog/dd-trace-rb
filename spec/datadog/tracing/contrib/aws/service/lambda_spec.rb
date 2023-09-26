# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/lambda'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Lambda do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:lambda) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'when function_name is present' do
    let(:function_name) { 'barfoo' }
    let(:params) { { function_name: function_name } }

    it 'sets functonname tag' do
      lambda.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_FUNCTION_NAME, function_name)
    end
  end
end
