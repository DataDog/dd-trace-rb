# typed: false

require 'datadog/tracing/contrib/hook'

require 'ddtrace'

RSpec.describe Datadog::Tracing::Contrib::Hook do
  subject(:hook) { described_class.new(name, target, span_options) }

  let(:name) { 'test_span' }
  let(:target) { 'Target#method' }
  let(:span_options) { {} }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        name: name,
        target: target,
        span_options: span_options
      )
    end

    context 'when span_options not provided' do
      subject(:hook) { described_class.new(name, target) }
      it do
        is_expected.to have_attributes(
          name: name,
          target: target,
          span_options: {}
        )
      end

      it { is_expected.to be_a_kind_of(described_class) }
    end
  end

  describe '#inject!' do
    subject(:inject!) { hook.inject! }

    it do
      inject!

      expect(hook).to have_attributes(hook: be_a_kind_of(Datadog::Instrumentation::Hook))
      expect(hook.hook.point.to_s).to eq(target)
    end
  end

  describe '#around' do
    subject(:around) { hook.around(&block) }
    let(:block) { nil }

    it { is_expected.to be_a_kind_of(described_class) }

    it do
      around
      expect(hook).to have_attributes(around_block: block)
    end
  end

  describe '::Env' do
    subject(:env) { Datadog::Tracing::Contrib::Hook::Env.new(env_hash) }
    let(:env_hash) { { self: self_instance, args: args, kwargs: kwargs } }
    let(:self_instance) { double('self') }
    let(:args) { double('args') }
    let(:kwargs) { double('kwargs') }

    it { is_expected.to have_attributes(self: self_instance, args: args, kwargs: kwargs) }
  end
end
