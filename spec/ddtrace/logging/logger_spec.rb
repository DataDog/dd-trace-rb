require 'spec_helper'

require 'logger'
require 'stringio'
require 'time'
require 'ddtrace'

RSpec.describe Datadog::Logging::Logger do
  subject(:logger) do
    described_class.new(buf).tap do |logger|
      logger.level = log_level
    end
  end
  let(:buf) { StringIO.new }
  # DEV: In older versions of Ruby `buf.string.lines` is an Enumerator and not an array
  let(:lines) { buf.string.lines.to_a }
  let(:log_level) { Logger::WARN }

  shared_examples 'behaves like a logger' do |level, level_name|
    let(:log_level) { level }
    let(:pattern_start) do
      "^#{level_name[0]}, \\[[T0-9\\-:.]+ #[0-9]+\\] #{level_name.rjust(5, ' ')} --"
    end
    let(:where) do
      return unless log_level == Logger::DEBUG || log_level == Logger::ERROR

      '\(.*?:in `[a-z_]+\'\) '
    end

    context "(#{level_name})" do
      before(:each) { logger.add(log_level) }

      it { expect(lines.length).to eq(1) }
      it { expect(lines[0]).to match(/#{pattern_start} ddtrace: \[ddtrace\] #{where}$/) }
    end

    context "(#{level_name}, message)" do
      before(:each) { logger.add(log_level, 'my message') }

      it { expect(lines.length).to eq(1) }
      it { expect(lines[0]).to match(/#{pattern_start} ddtrace: \[ddtrace\] #{where}my message$/) }
    end

    context "(#{level_name}) {}" do
      before(:each) { logger.add(log_level) { 'my message' } }

      it { expect(lines.length).to eq(1) }
      it { expect(lines[0]).to match(/#{pattern_start} ddtrace: \[ddtrace\] #{where}my message$/) }
    end

    context "(#{level_name}, message, progname)" do
      before(:each) { logger.add(log_level, 'my message', 'progname') }

      it { expect(lines.length).to eq(1) }
      it { expect(lines[0]).to match(/#{pattern_start} progname: \[ddtrace\] #{where}my message$/) }
    end

    context "(#{level_name}, message = nil, progname)" do
      before(:each) { logger.add(log_level, nil, 'progname') }

      it { expect(lines.length).to eq(1) }
      it { expect(lines[0]).to match(/#{pattern_start} ddtrace: \[ddtrace\] #{where}progname$/) }
    end
  end

  describe '#add' do
    context 'WARN' do
      include_examples 'behaves like a logger', Logger::WARN, 'WARN'
    end

    context 'INFO' do
      include_examples 'behaves like a logger', Logger::INFO, 'INFO'
    end

    context 'ERROR' do
      include_examples 'behaves like a logger', Logger::ERROR, 'ERROR'
    end

    context 'DEBUG' do
      include_examples 'behaves like a logger', Logger::DEBUG, 'DEBUG'
    end
  end
end
