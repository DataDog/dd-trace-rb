require 'spec_helper'
require 'ddtrace/tasks/exec'

RSpec.describe Datadog::Tasks::Exec do
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

    before do
      # Must stub the call out or test will prematurely terminate.
      expect(Kernel).to receive(:exec)
        .with(*args)
        .and_return(result)
    end

    context 'when RUBOPT is not defined' do
      it 'runs the task with preloads' do
        is_expected.to be(result)

        # Expect preloading to have been attached
        task.rubyopts.each do |opt|
          expect(ENV['RUBYOPT']).to include(opt)
        end
      end
    end

    context 'when RUBYOPT is defined' do
      before { ENV['RUBYOPT'] = start_opts }
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
  end

  describe '#rubyopts' do
    subject(:rubyopts) { task.rubyopts }
    it { is_expected.to eq(['-rddtrace/profiling/preload']) }
  end
end
