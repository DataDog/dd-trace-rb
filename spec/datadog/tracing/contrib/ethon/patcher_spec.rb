require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'ethon'

RSpec.describe Datadog::Tracing::Contrib::Ethon::Patcher do
  describe '.patch' do
    it 'adds EasyPatch to ancestors of Easy class' do
      described_class.patch

      expect(Ethon::Easy.ancestors).to include(Datadog::Tracing::Contrib::Ethon::EasyPatch)
    end

    it 'adds MultiPatch to ancestors of Multi class' do
      described_class.patch

      expect(Ethon::Multi.ancestors).to include(Datadog::Tracing::Contrib::Ethon::MultiPatch)
    end
  end
end
