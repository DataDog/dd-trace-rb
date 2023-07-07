require 'datadog/ci/contrib/support/spec_helper'
require 'datadog/ci/contrib/minitest/patcher'

require 'minitest'

RSpec.describe Datadog::CI::Contrib::Minitest::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:test) { Minitest::Test }

    context 'is patched' do
      it 'has a custom bases' do
        expect(test.ancestors).to include(Datadog::CI::Contrib::Minitest::TestHelper)
      end
    end
  end
end
