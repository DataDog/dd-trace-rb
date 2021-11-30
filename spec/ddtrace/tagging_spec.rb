# typed: ignore
require 'spec_helper'

require 'ddtrace/tagging'

RSpec.describe Datadog::Tagging do
  context 'when included' do
    subject(:test_class) { Class.new { include Datadog::Tagging } }

    describe '::ancestors' do
      subject(:ancestors) { test_class.ancestors }

      it 'has all of the tagging behavior in correct order' do
        expect(ancestors.first(5)).to include(
          described_class::Analytics,
          described_class::Metadata
        )
      end
    end
  end
end
