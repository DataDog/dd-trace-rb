require 'datadog/ci/contrib/support/spec_helper'
require 'datadog/ci/contrib/rspec/patcher'

require 'rspec'

RSpec.describe Datadog::CI::Contrib::RSpec::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:example) { RSpec::Core::Example }

    context 'is patched' do
      it 'has a custom bases' do
        expect(example.ancestors).to include(Datadog::CI::Contrib::RSpec::Example::InstanceMethods)
      end
    end
  end
end
