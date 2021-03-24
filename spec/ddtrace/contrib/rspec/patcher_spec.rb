require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/rspec/patcher'

require 'rspec'

RSpec.describe Datadog::Contrib::RSpec::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:example) { RSpec::Core::Example }

    context 'is patched' do
      it 'has a custom bases' do
        expect(example.ancestors).to include(Datadog::Contrib::RSpec::Example::InstanceMethods)
      end
    end
  end
end
