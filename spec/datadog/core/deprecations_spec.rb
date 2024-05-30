require 'spec_helper'

require 'datadog/core/deprecations'

RSpec.describe Datadog::Core::Deprecations do
  context 'when extended' do
    subject(:test_class) { Class.new { extend Datadog::Core::Deprecations } }

    describe '.log_deprecation' do
      subject(:log_deprecation) { call_log_deprecation }

      let(:options) { {} }
      let(:message) { 'Longer allowed.' }

      def call_log_deprecation
        test_class.log_deprecation(**options) { message }
      end

      context 'by default' do
        it 'warns with enforcement message' do
          expect(Datadog.logger).to receive(:warn) do |&block|
            expect(block.call).to eq('Longer allowed. This will be enforced in the next major release.')
          end
          log_deprecation
        end

        it 'does not limit messages' do
          expect(Datadog.logger).to receive(:warn).twice
          2.times { call_log_deprecation }
        end
      end

      context 'with disallowed_next_major:' do
        let(:options) { { disallowed_next_major: disallowed_next_major } }

        context 'true' do
          let(:disallowed_next_major) { true }

          it 'warns with enforcement message' do
            expect(Datadog.logger).to receive(:warn) do |&block|
              expect(block.call).to eq('Longer allowed. This will be enforced in the next major release.')
            end
            log_deprecation
          end
        end

        context 'false' do
          let(:disallowed_next_major) { false }

          it 'warns with enforcement message' do
            expect(Datadog.logger).to receive(:warn) do |&block|
              expect(block.call).to eq('Longer allowed.')
            end
            log_deprecation
          end
        end
      end

      context 'with key:' do
        let(:options) { { key: key } }

        context 'nil' do
          let(:key) { nil }

          it 'does not limit messages' do
            expect(Datadog.logger).to receive(:warn).twice
            2.times { call_log_deprecation }
          end
        end

        context 'Symbol' do
          let(:key) { :deprecated_setting }

          it 'limits messages' do
            expect(Datadog.logger).to receive(:warn).once
            2.times { call_log_deprecation }
          end
        end

        context 'String' do
          let(:key) { 'deprecated_setting' }

          it 'limits messages' do
            expect(Datadog.logger).to receive(:warn).once
            2.times { call_log_deprecation }
          end
        end
      end
    end
  end
end
