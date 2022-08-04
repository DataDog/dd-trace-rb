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

  describe '#invoke' do
    subject(:invoke) { hook.invoke(stack, env) }
    let(:stack) { double('stack') }
    let(:env) { double('env') }
    let(:return_object) { double('return') }

    before do
      allow(stack).to receive(:call).and_return({ return: return_object })
      allow(env).to receive(:[]).and_return(double('attr'))
    end

    context 'when around block provided' do
      let(:block) { proc { |_env, _span, _trace, &block| block.call } }

      before do
        hook.around(&block)
      end

      it do
        res = invoke
        expect(stack).to have_received(:call).with(env)
        expect(res).to be(return_object)
      end
    end

    context 'when around block not provided' do
      it do
        res = invoke
        expect(stack).to have_received(:call).with(env)
        expect(res).to be(return_object)
      end
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
