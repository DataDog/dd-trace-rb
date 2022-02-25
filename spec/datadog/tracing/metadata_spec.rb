# typed: ignore

require 'spec_helper'

require 'datadog/tracing/metadata'
require 'datadog/tracing/metadata/analytics'
require 'datadog/tracing/metadata/tagging'

RSpec.describe Datadog::Tracing::Metadata do
  context 'when included' do
    subject(:test_class) { Class.new { include Datadog::Tracing::Metadata } }

    describe '::ancestors' do
      subject(:ancestors) { test_class.ancestors }

      it 'has all of the tagging behavior in correct order' do
        expect(ancestors.first(5)).to include(
          described_class::Analytics,
          described_class::Tagging
        )
      end
    end
  end
end
