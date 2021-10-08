# typed: false
require 'datadog/ci/spec_helper'

require 'datadog/ci/test'

RSpec.describe Datadog::CI::Test do
  let(:tracer) { instance_double(Datadog::Tracer) }
  let(:span_name) { 'span name' }

  shared_examples_for 'default test span tags' do
    it do
      expect(Datadog::Contrib::Analytics)
        .to have_received(:set_measured)
        .with(span)
    end

    it do
      expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND))
        .to eq(Datadog::CI::Ext::AppTypes::TEST)
    end

    it do
      Datadog::CI::Ext::Environment.tags(ENV).each do |key, value|
        expect(span.get_tag(key))
          .to eq(value)
      end
    end
  end

  describe '::trace' do
    let(:options) { {} }

    context 'when given a block' do
      subject(:trace) { described_class.trace(tracer, span_name, options, &block) }
      let(:span) { Datadog::SpanOperation.new(span_name) }
      let(:block) { proc { |s| block_spy.call(s) } }
      # rubocop:disable RSpec/VerifiedDoubles
      let(:block_result) { double('result') }
      let(:block_spy) { spy('block') }
      # rubocop:enable RSpec/VerifiedDoubles

      before do
        allow(block_spy).to receive(:call).and_return(block_result)

        allow(tracer)
          .to receive(:trace) do |trace_span_name, trace_span_options, &trace_block|
            expect(trace_span_name).to be(span_name)
            expect(trace_span_options).to eq({ span_type: Datadog::CI::Ext::AppTypes::TEST })
            trace_block.call(span)
          end

        allow(Datadog::Contrib::Analytics).to receive(:set_measured)

        trace
      end

      it_behaves_like 'default test span tags'
      it { expect(block_spy).to have_received(:call).with(span) }
      it { is_expected.to be(block_result) }
    end

    context 'when not given a block' do
      subject(:trace) { described_class.trace(tracer, span_name, options) }
      let(:span) { Datadog::SpanOperation.new(span_name) }

      before do
        allow(tracer)
          .to receive(:trace)
          .with(
            span_name,
            { span_type: Datadog::CI::Ext::AppTypes::TEST }
          )
          .and_return(span)

        allow(Datadog::Contrib::Analytics).to receive(:set_measured)

        trace
      end

      it_behaves_like 'default test span tags'
      it { is_expected.to be(span) }
    end
  end

  describe '::set_tags!' do
    subject(:set_tags!) { described_class.set_tags!(span, tags) }
    let(:span) { Datadog::SpanOperation.new(span_name) }
    let(:tags) { {} }

    before do
      allow(Datadog::Contrib::Analytics).to receive(:set_measured)
    end

    it_behaves_like 'default test span tags' do
      before { set_tags! }
    end

    context 'when span has a context' do
      let(:context) { instance_double(Datadog::Context) }

      before do
        allow(span).to receive(:context).and_return(context)
        allow(context).to receive(:origin=)
        set_tags!
      end

      it do
        expect(context)
          .to have_received(:origin=)
          .with(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
      end
    end

    context 'when :framework is given' do
      let(:tags) { { framework: framework } }
      let(:framework) { 'framework' }

      before { set_tags! }

      it do
        expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK))
          .to eq(framework)
      end
    end

    context 'when :framework_version is given' do
      let(:tags) { { framework_version: framework_version } }
      let(:framework_version) { 'framework_version' }

      before { set_tags! }

      it do
        expect(span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION))
          .to eq(framework_version)
      end
    end

    context 'when :test_name is given' do
      let(:tags) { { test_name: test_name } }
      let(:test_name) { 'test name' }

      before { set_tags! }

      it do
        expect(span.get_tag(Datadog::CI::Ext::Test::TAG_NAME))
          .to eq(test_name)
      end
    end

    context 'when :test_suite is given' do
      let(:tags) { { test_suite: test_suite } }
      let(:test_suite) { 'test suite' }

      before { set_tags! }

      it do
        expect(span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE))
          .to eq(test_suite)
      end
    end

    context 'when :test_type is given' do
      let(:tags) { { test_type: test_type } }
      let(:test_type) { 'test type' }

      before { set_tags! }

      it do
        expect(span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE))
          .to eq(test_type)
      end
    end

    context 'with environment runtime information' do
      context 'for the architecture platform' do
        subject(:tag) do
          set_tags!
          span.get_tag(Datadog::CI::Ext::Test::TAG_OS_ARCHITECTURE)
        end

        it { is_expected.to eq('x86_64').or eq('i686').or start_with('arm') }
      end

      context 'for the OS platform' do
        subject(:tag) do
          set_tags!
          span.get_tag(Datadog::CI::Ext::Test::TAG_OS_PLATFORM)
        end

        context 'with Linux', if: PlatformHelpers.linux? do
          it { is_expected.to start_with('linux') }
        end

        context 'with Mac OS', if: PlatformHelpers.mac? do
          it { is_expected.to start_with('darwin') }
        end

        it 'returns a valid string' do
          is_expected.to be_a(String)
        end
      end

      context 'for the runtime name' do
        subject(:tag) do
          set_tags!
          span.get_tag(Datadog::CI::Ext::Test::TAG_RUNTIME_NAME)
        end

        context 'with MRI', if: PlatformHelpers.mri? do
          it { is_expected.to eq('ruby') }
        end

        context 'with JRuby', if: PlatformHelpers.jruby? do
          it { is_expected.to eq('jruby') }
        end

        context 'with TruffleRuby', if: PlatformHelpers.truffleruby? do
          it { is_expected.to eq('truffleruby') }
        end

        it 'returns a valid string' do
          is_expected.to be_a(String)
        end
      end

      context 'for the runtime version' do
        subject(:tag) do
          set_tags!
          span.get_tag(Datadog::CI::Ext::Test::TAG_RUNTIME_VERSION)
        end

        context 'with MRI', if: PlatformHelpers.mri? do
          it { is_expected.to match(/^[23]\./) }
        end

        context 'with JRuby', if: PlatformHelpers.jruby? do
          it { is_expected.to match(/^9\./) }
        end

        context 'with TruffleRuby', if: PlatformHelpers.truffleruby? do
          it { is_expected.to match(/^2\d\./) }
        end

        it 'returns a valid string' do
          is_expected.to be_a(String)
        end
      end
    end
  end

  describe '::passed!' do
    subject(:passed!) { described_class.passed!(span) }
    let(:span) { instance_double(Datadog::SpanOperation) }

    before do
      allow(span).to receive(:set_tag)
      passed!
    end

    it do
      expect(span)
        .to have_received(:set_tag)
        .with(
          Datadog::CI::Ext::Test::TAG_STATUS,
          Datadog::CI::Ext::Test::Status::PASS
        )
    end
  end

  describe '::failed!' do
    let(:span) { instance_double(Datadog::SpanOperation) }

    before do
      allow(span).to receive(:status=)
      allow(span).to receive(:set_tag)
      allow(span).to receive(:set_error)
      failed!
    end

    shared_examples 'failed test span' do
      it do
        expect(span)
          .to have_received(:status=)
          .with(1)
      end

      it do
        expect(span)
          .to have_received(:set_tag)
          .with(
            Datadog::CI::Ext::Test::TAG_STATUS,
            Datadog::CI::Ext::Test::Status::FAIL
          )
      end
    end

    context 'when no exception is given' do
      subject(:failed!) { described_class.failed!(span) }

      it_behaves_like 'failed test span'
      it { expect(span).to_not have_received(:set_error) }
    end

    context 'when exception is given' do
      subject(:failed!) { described_class.failed!(span, exception) }
      let(:exception) { instance_double(StandardError) }

      it_behaves_like 'failed test span'

      it do
        expect(span)
          .to have_received(:set_error)
          .with(exception)
      end
    end
  end

  describe '::skipped!' do
    let(:span) { instance_double(Datadog::SpanOperation) }

    before do
      allow(span).to receive(:set_tag)
      allow(span).to receive(:set_error)
      skipped!
    end

    shared_examples 'skipped test span' do
      it do
        expect(span)
          .to have_received(:set_tag)
          .with(
            Datadog::CI::Ext::Test::TAG_STATUS,
            Datadog::CI::Ext::Test::Status::SKIP
          )
      end
    end

    context 'when no exception is given' do
      subject(:skipped!) { described_class.skipped!(span) }

      it_behaves_like 'skipped test span'
      it { expect(span).to_not have_received(:set_error) }
    end

    context 'when exception is given' do
      subject(:skipped!) { described_class.skipped!(span, exception) }
      let(:exception) { instance_double(StandardError) }

      it_behaves_like 'skipped test span'

      it do
        expect(span)
          .to have_received(:set_error)
          .with(exception)
      end
    end
  end
end
