# typed: ignore
require 'spec_helper'

require 'ddtrace/tagging'

RSpec.describe Datadog::Tagging do
  context 'when included' do
    subject(:test_class) { Class.new { include Datadog::Tagging } }

    describe '::ancestors' do
      subject(:ancestors) { test_class.ancestors }

      it 'has all of the tagging behavior in correct order' do
        expect(ancestors.first(5)).to eq(
          [
            described_class::ManualTracing,
            described_class::Analytics,
            test_class,
            described_class::Metadata,
            described_class
          ]
        )
      end
    end
  end
end
