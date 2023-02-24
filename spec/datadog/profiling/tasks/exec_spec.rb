require 'spec_helper'
require 'datadog/profiling/tasks/exec'

RSpec.describe Datadog::Profiling::Tasks::Exec do
  subject(:task) { described_class.new(args) }

  let(:args) { ['ruby', '-e', '"RUBY_VERSION"'] }

  describe '::new' do
    it { is_expected.to have_attributes(args: args) }
  end

  describe '#run' do
    subject(:run) { task.run }

    let(:result) { double('result') }

    around do |example|
      # Make sure RUBYOPT is returned to its original state.
      original_opts = ENV['RUBYOPT']
      example.run
      ENV['RUBYOPT'] = original_opts
    end

    context 'when RUBYOPT is not defined' do
      before do
        # Must stub the call out or test will prematurely terminate.
        expect(Kernel).to receive(:exec)
          .with(*args)
          .and_return(result)
      end

      it 'runs the task with preloads' do
        is_expected.to be(result)

        # Expect preloading to have been attached
        task.rubyopts.each do |opt|
          expect(ENV['RUBYOPT']).to include(opt)
        end
      end
    end

    context 'when RUBYOPT is defined' do
      before do
        # Must stub the call out or test will prematurely terminate.
        expect(Kernel).to receive(:exec)
          .with(*args)
          .and_return(result)

        ENV['RUBYOPT'] = start_opts
      end

      let(:start_opts) { 'start_opts' }

      it 'runs the task with additional preloads' do
        is_expected.to be(result)

        # Expect original RUBYOPT to have been preserved
        expect(ENV['RUBYOPT']).to include(start_opts)

        # Expect preloading to have been attached
        task.rubyopts.each do |opt|
          expect(ENV['RUBYOPT']).to include(opt)
        end
      end
    end

    context 'when exec fails' do
      before do
        allow(Kernel).to receive(:exit)
        allow(Kernel).to receive(:warn)
      end

      context 'when command does not exist' do
        before do
          allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT)
        end

        it 'triggers a VM exit with error code 127' do
          expect(Kernel).to receive(:exit).with(127)

          run
        end

        it 'logs an error message' do
          expect(Kernel).to receive(:warn) do |message|
            expect(message).to include('ddtracerb exec failed')
          end

          run
        end
      end

      context 'when command is not executable' do
        [Errno::EACCES, Errno::ENOEXEC].each do |error|
          context "when exec fails with #{error}" do
            before do
              allow(Kernel).to receive(:exec).and_raise(error)
            end

            it 'triggers a VM exit with error code 126' do
              expect(Kernel).to receive(:exit).with(126)

              run
            end

            it 'logs an error message' do
              expect(Kernel).to receive(:warn) do |message|
                expect(message).to include('ddtracerb exec failed')
              end

              run
            end
          end
        end
      end
    end
  end

  describe '#rubyopts' do
    subject(:rubyopts) { task.rubyopts }

    it { is_expected.to eq(['-rdatadog/profiling/preload']) }
  end
end
