# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/environment/execution'

RSpec.describe Datadog::Core::Environment::Execution do
  describe '#development?' do
    subject(:development?) { described_class.development? }

    context 'when in an RSpec test' do
      it { is_expected.to eq(true) }
    end

    context 'when not in an RSpec test' do
      # RSpec is detected through the $PROGRAM_NAME.
      # Changing it will make RSpec detection to return false.
      #
      # We change the $PROGRAM_NAME instead of stubbing
      # `Datadog::Core::Environment::Execution.rspec?` because
      # otherwise we'll have no real test for non-RSpec cases.
      around do |example|
        original = $PROGRAM_NAME
        $PROGRAM_NAME = 'not-rspec'
        example.run
      ensure
        $PROGRAM_NAME = original
      end

      let(:repl_script) do
        <<-RUBY
          # Load the working directory version of `ddtrace`
          lib = File.expand_path('lib', __dir__)
          $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
          require 'datadog/core/environment/execution'

          # Print actual value to STDERR, as STDOUT tends to have more noise in REPL sessions.
          STDERR.print Datadog::Core::Environment::Execution.development?
        RUBY
      end

      it 'ensure RSpec detection returns false' do
        is_expected.to eq(false)
      end

      context 'when in an IRB session' do
        it 'returns true' do
          _, err, = Open3.capture3('irb', '--noprompt', '--noverbose', stdin_data: repl_script)
          expect(err).to end_with('true')
        end
      end

      context 'when in a Pry session' do
        it 'returns true' do
          Tempfile.create do |f|
            f.write(repl_script)
            f.close

            out, = Open3.capture2e('pry', '--noprompt', f.path)
            expect(out).to eq('true')
          end
        end
      end

      context 'when in a Minitest test' do
        it 'returns true' do
          expect_in_fork do
            # Minitest reads CLI arguments, but the current process has RSpec
            # arguments that are not relevant (nor compatible) with Minitest.
            # This happens inside a fork, thus we don't have to reset it.
            Kernel.const_set('ARGV', [])

            require 'minitest/autorun'

            is_expected.to eq(true)
          end
        end
      end
    end
  end
end
