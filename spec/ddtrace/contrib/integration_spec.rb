require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Integration do
  describe 'implemented' do
    subject(:integration_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'instance behavior' do
      subject(:integration_object) { integration_class.new(name) }
      let(:name) { :foo }

      it { is_expected.to be_a_kind_of(Datadog::Contrib::Configurable) }
      it { is_expected.to be_a_kind_of(Datadog::Contrib::Patchable) }
      it { is_expected.to be_a_kind_of(Datadog::Contrib::Registerable) }
    end
  end
end
