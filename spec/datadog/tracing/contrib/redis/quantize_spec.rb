require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/redis/quantize'

RSpec.describe Datadog::Tracing::Contrib::Redis::Quantize do
  describe '#format_arg' do
    subject(:output) { described_class.format_arg(arg) }

    context 'given' do
      context 'nil' do
        let(:arg) { nil }

        it { is_expected.to eq('') }
      end

      context 'an empty string' do
        let(:arg) { '' }

        it { is_expected.to eq('') }
      end

      context 'a string under the limit' do
        let(:arg) { 'HGETALL' }

        it { is_expected.to eq(arg) }
      end

      context 'a string up to limit' do
        let(:arg) { 'A' * 50 }

        it { is_expected.to eq(arg) }
      end

      context 'a string over the limit by one' do
        let(:arg) { 'B' * 101 }

        it { is_expected.to eq("#{'B' * 47}...") }
      end

      context 'a string over the limit by a lot' do
        let(:arg) { 'C' * 1000 }

        it { is_expected.to eq("#{'C' * 47}...") }
      end

      context 'an object that can\'t be converted to a string' do
        let(:arg) { object_class.new }
        let(:object_class) do
          Class.new do
            def to_s
              raise "can't make a string of me"
            end
          end
        end

        it { is_expected.to eq('?') }
      end

      context 'an invalid byte sequence' do
        # \255 is off-limits https://en.wikipedia.org/wiki/UTF-8#Codepage_layout
        let(:arg) { "SET foo bar\255" }

        it { is_expected.to eq('SET foo bar') }
      end
    end
  end

  describe '#format_command_args' do
    subject(:output) { described_class.format_command_args(args) }

    context 'given an array' do
      context 'simple command' do
        context 'string' do
          let(:args) { %w[set KEY VALUE] }

          it { is_expected.to eq('SET KEY VALUE') }
        end

        context 'uppercase string' do
          let(:args) { %w[SET KEY VALUE] }

          it { is_expected.to eq('SET KEY VALUE') }
        end

        context 'symbol' do
          let(:args) { [:set, 'KEY', 'VALUE'] }

          it { is_expected.to eq('SET KEY VALUE') }
        end

        context 'nested array' do
          context 'string' do
            let(:args) { [%w[set KEY VALUE]] }

            it { is_expected.to eq('SET KEY VALUE') }
          end

          context 'uppercase string' do
            let(:args) { [%w[SET KEY VALUE]] }

            it { is_expected.to eq('SET KEY VALUE') }
          end

          context 'symbol' do
            let(:args) { [[:set, 'KEY', 'VALUE']] }

            it { is_expected.to eq('SET KEY VALUE') }
          end
        end
      end

      context 'of many very long args (over the limit)' do
        let(:args) { Array.new(20) { 'X' * 90 } }

        it { expect(output.length).to eq(500) }
        it { expect(output[496..499]).to eq('X...') }
      end

      context 'authentication' do
        context 'all strings' do
          let(:args) { %w[auth data dog] }

          it { is_expected.to eq('AUTH ?') }
        end

        context 'all strings uppercase' do
          let(:args) { %w[AUTH data dog] }

          it { is_expected.to eq('AUTH ?') }
        end

        context 'with symbol' do
          let(:args) { [:auth, 'data', 'dog'] }

          it { is_expected.to eq('AUTH ?') }
        end

        context 'nested array' do
          context 'strings' do
            let(:args) { [%w[auth data dog]] }

            it { is_expected.to eq('AUTH ?') }
          end

          context 'uppercase strings' do
            let(:args) { [%w[AUTH data dog]] }

            it { is_expected.to eq('AUTH ?') }
          end

          context 'symbol' do
            let(:args) { [[:auth, 'data', 'dog']] }

            it { is_expected.to eq('AUTH ?') }
          end
        end
      end
    end
  end

  describe '#get_verb' do
    subject(:output) { described_class.get_verb(args) }

    context 'given an array' do
      context 'string' do
        let(:args) { %w[set KEY VALUE] }

        it { is_expected.to eq('SET') }
      end

      context 'uppercase string' do
        let(:args) { [%w[SET KEY VALUE]] }

        it { is_expected.to eq('SET') }
      end

      context 'symbol' do
        let(:args) { [:set, 'KEY', 'VALUE'] }

        it { is_expected.to eq('SET') }
      end

      context 'given an multi verb commands' do
        let(:args) { [:acl, 'CAT', 'categoryname'] }

        it { is_expected.to eq('ACL CAT') }
      end

      context 'given an multi verb commands' do
        let(:args) { [:acl, 'HELP'] }

        it { is_expected.to eq('ACL HELP') }
      end
    end

    context 'nested array' do
      context 'symbol' do
        let(:args) { [[:set, 'KEY', 'VALUE']] }

        it { is_expected.to eq('SET') }
      end

      context 'string' do
        let(:args) { [%w[set KEY VALUE]] }

        it { is_expected.to eq('SET') }
      end

      context 'uppercase string' do
        let(:args) { [%w[SET KEY VALUE]] }

        it { is_expected.to eq('SET') }
      end

      context 'given an multi verb commands' do
        let(:args) { [:acl, 'CAT', 'categoryname'] }

        it { is_expected.to eq('ACL CAT') }
      end

      context 'given an multi verb commands' do
        let(:args) { [:acl, 'HELP'] }

        it { is_expected.to eq('ACL HELP') }
      end
    end
  end
end
