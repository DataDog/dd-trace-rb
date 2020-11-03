# encoding: utf-8

require 'spec_helper'
require 'ddtrace/runtime/identity'

RSpec.describe Datadog::Runtime::Identity do
  describe '::id' do
    subject(:id) { described_class.id }

    it { is_expected.to be_a_kind_of(String) }

    context 'when invoked twice' do
      it { expect(described_class.id).to eq(described_class.id) }
    end

    context 'when invoked around a fork' do
      before { skip unless PlatformHelpers.supports_fork? }

      let(:before_fork_id) { described_class.id }
      let(:inside_fork_id) { described_class.id }
      let(:after_fork_id) { described_class.id }

      it do
        # Check before forking
        expect(before_fork_id).to be_a_kind_of(String)

        # Invoke in fork, make sure expectations run before continuing.
        expect_in_fork do
          expect(inside_fork_id).to be_a_kind_of(String)
          expect(inside_fork_id).to_not eq(before_fork_id)
        end

        # Check after forking
        expect(after_fork_id).to eq(before_fork_id)
      end
    end
  end
end
