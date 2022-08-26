# typed: ignore

require 'datadog/tracing/contrib/hook'

require 'ddtrace'

RSpec.describe Datadog::Tracing::Contrib::Hook do
  subject(:hook) { described_class.new(target, name, span_options) }

  let(:name) { 'test_span' }
  let(:target) { 'Target#method' }
  let(:span_options) { {} }

  describe '::supported?' do
    subject(:supported?) { described_class.supported? }

    context 'when there is an unsupported_reason' do
      before { allow(described_class).to receive(:unsupported_reason).and_return('Unsupported, sorry :(') }

      it { is_expected.to be false }
    end

    context 'when there is no unsupported_reason' do
      before { allow(described_class).to receive(:unsupported_reason).and_return(nil) }

      it { is_expected.to be true }
    end
  end

  describe '::unsupported_reason' do
    subject(:unsupported_reason) { described_class.unsupported_reason }

    context 'when datadog-instrumentation gem' do
      context 'is not available' do
        include_context 'loaded gems', :'datadog-instrumentation' => nil

        before do
          hide_const('::Datadog::Instrumentation')
        end

        it { is_expected.to include 'Missing datadog-instrumentation' }
      end

      context 'is not yet loaded' do
        before do
          hide_const('::Datadog::Instrumentation')
          allow(described_class).to receive(:datadog_instrumentation_gem_unavailable?).and_return(nil)
        end

        context 'when datadog-instrumentation does not load correctly' do
          before { allow(described_class).to receive(:datadog_instrumentation_loaded_successfully?).and_return(false) }

          it { is_expected.to include 'error loading' }
        end

        context 'when datadog-instrumentation loads successfully' do
          before { allow(described_class).to receive(:datadog_instrumentation_loaded_successfully?).and_return(true) }

          it { is_expected.to be nil }
        end
      end
    end
  end

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        name: name,
        target: target,
        span_options: span_options
      )
    end

    context 'when span_options not provided' do
      subject(:hook) { described_class.new(target, name) }
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
    before do
      require 'datadog/instrumentation'
    end

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
      require 'datadog/instrumentation'
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

  describe '#disable!' do
    subject(:disable!) { hook.disable! }

    before do
      hook.inject!
    end

    it do
      expect { disable! }.to change { hook.disabled? }.from(false).to(true)
    end
  end

  describe '#enable!' do
    subject(:enable!) { hook.enable! }

    before do
      hook.inject!
      hook.disable!
    end

    it do
      expect { enable! }.to change { hook.disabled? }.to(false)
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
