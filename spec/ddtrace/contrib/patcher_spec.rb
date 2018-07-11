require 'spec_helper'

require 'ddtrace'
require 'ddtrace/contrib/patcher'

RSpec.describe Datadog::Contrib::Patcher do
  describe 'implemented' do
    subject(:patcher_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'class behavior' do
      describe '#patch' do
        subject(:patch) { patcher_class.patch }
        it { expect { patch }.to raise_error(NotImplementedError) }
      end
    end

    describe 'instance behavior' do
      subject(:patcher_object) { patcher_class.new }

      it { is_expected.to be_a_kind_of(Datadog::Patcher) }

      describe '#patch' do
        subject(:patch) { patcher_object.patch }
        it { expect { patch }.to raise_error(NotImplementedError) }
      end
    end
  end
end
