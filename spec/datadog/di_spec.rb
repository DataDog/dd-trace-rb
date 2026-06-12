require 'spec_helper'

RSpec.describe(Datadog::DI) do
  describe 'instrumentation counters' do
    before do
      described_class.remove_instance_variable('@instrumented_count')
    rescue
      nil
    end

    # The retrieval of kind-scoped count is tested in the inc/dec blocks.
    describe '#instrumented_count' do
      context 'when the counter is not initialized' do
        it 'is 0' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          expect(described_class.instance_variable_get('@instrumented_count')).to be nil
        end
      end

      context 'when counter is incremented' do
        it 'is 1' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count).to eq 1
        end
      end

      # Important: this test also exercises initialization of state in
      # the increment method.
      context 'when counter is incremented then decremented' do
        it 'is 0' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count).to eq 1

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count).to eq 0
        end
      end

      # Important: this test also exercises initialization of state in
      # the decrement method.
      context 'when counter is decremented then incremented' do
        it 'is 1' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count).to eq 1
        end
      end

      context 'when counter is decremented into negative' do
        it 'is 0 and warns' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          expect(described_class.instrumented_count).to eq 0

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count).to eq 0
        end
      end
    end

    describe '#instrumented_count_inc' do
      context 'valid kind' do
        it 'increases only the respective counter' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          described_class.instrumented_count_inc(:line)

          expect(described_class.instrumented_count(:line)).to eq 1
          expect(described_class.instrumented_count(:method)).to eq 0
        end
      end

      context 'invalid kind' do
        it 'raises an exception' do
          expect do
            described_class.instrumented_count_inc(:foo)
          end.to raise_error(ArgumentError, /Invalid kind: foo/)
        end
      end
    end

    describe '#instrumented_count_dec' do
      context 'valid kind' do
        it 'deccreases only the respective counter' do
          expect(described_class.instance_variable_get('@instrumented_count')).to be nil

          described_class.instrumented_count_inc(:line)
          described_class.instrumented_count_inc(:method)

          expect(described_class.instance_variable_get('@instrumented_count')).to eq(line: 1, method: 1)

          described_class.instrumented_count_dec(:line)

          expect(described_class.instrumented_count(:line)).to eq 0
          expect(described_class.instrumented_count(:method)).to eq 1
        end
      end

      context 'invalid kind' do
        it 'raises an exception' do
          expect do
            described_class.instrumented_count_inc(:foo)
          end.to raise_error(ArgumentError, /Invalid kind: foo/)
        end
      end
    end
  end

  describe '.unsupported_reason' do
    # Single source of truth for DI's build-time preconditions. Consumed by
    # DI::Component.build (for the build-time log) and by
    # DI::Remote.handle_rc_enablement (for the RC-time warn when the
    # component was not built). Order of checks is most-actionable first.

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.remote.enabled = true
        s.dynamic_instrumentation.internal.development = true
      end
    end

    context 'when all preconditions are met' do
      # Stub respond_to?(:exception_message) so this test exercises the
      # all-preconditions-met branch on builds without the DI C extension
      # compiled (e.g. spec:main). RUBY_VERSION is stubbed because the
      # version check fires before the C-extension check; without the
      # stub this test would fail on Ruby 2.5 (which is otherwise
      # supported by spec:main). The test's subject is the precondition
      # logic itself, not the actual platform.
      before do
        stub_const('RUBY_VERSION', '3.0.0')
        allow(described_class).to receive(:respond_to?).and_call_original
        allow(described_class).to receive(:respond_to?).with(:exception_message).and_return(true)
      end

      it 'returns nil' do
        expect(described_class.unsupported_reason(settings)).to be_nil
      end
    end

    context 'when Remote Configuration is disabled' do
      before { settings.remote.enabled = false }

      it 'returns the RC reason with the docs URL' do
        expect(described_class.unsupported_reason(settings))
          .to match(%r{Remote Configuration is not enabled.*docs\.datadoghq\.com/agent/remote_config})
      end
    end

    context 'when settings does not respond to :dynamic_instrumentation' do
      # In unusual configurations (test doubles, partial Settings) the
      # DI namespace may be absent. Without the guard the line
      # `settings.dynamic_instrumentation.internal.development` would
      # raise NoMethodError and prevent Remote.handle_rc_enablement
      # from emitting the customer-facing warn.
      let(:settings) { double('settings') }

      before do
        allow(settings).to receive(:respond_to?).with(:dynamic_instrumentation).and_return(false)
      end

      it 'returns a DI-not-available reason without raising' do
        expect(described_class.unsupported_reason(settings))
          .to match(/dynamic instrumentation settings are not available/)
      end
    end

    context 'when running on a non-MRI engine' do
      before { stub_const('RUBY_ENGINE', 'truffleruby') }

      it 'names the engine' do
        expect(described_class.unsupported_reason(settings))
          .to match(/MRI is required.*truffleruby/)
      end
    end

    context 'when running on Ruby older than 2.6' do
      before { stub_const('RUBY_VERSION', '2.5.9') }

      it 'names the version' do
        expect(described_class.unsupported_reason(settings))
          .to match(/Ruby 2\.6\+ is required.*2\.5\.9/)
      end
    end

    context 'when the C extension is not loaded' do
      before do
        # Neutralize the earlier RUBY_VERSION < '2.6' check so this context
        # reaches the C-extension branch when the spec runs on Ruby 2.5.
        # Same pattern as the non-MRI context's stub_const('RUBY_ENGINE', ...).
        stub_const('RUBY_VERSION', '3.0.0')
        allow(described_class).to receive(:respond_to?).and_call_original
        allow(described_class).to receive(:respond_to?).with(:exception_message).and_return(false)
      end

      it 'returns the C-extension reason' do
        expect(described_class.unsupported_reason(settings))
          .to match(/C extension is not available/)
      end
    end

    context 'when called with no argument' do
      it 'falls back to Datadog.configuration' do
        # The helper must be callable from the RC handler, which doesn't have
        # settings in lexical scope.
        expect { described_class.unsupported_reason }.not_to raise_error
      end
    end
  end
end
