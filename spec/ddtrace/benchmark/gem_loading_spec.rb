require 'spec_helper'

if !PlatformHelpers.jruby? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
  require 'benchmark/memory'
  require 'memory_profiler'
end

RSpec.describe "Gem loading" do
  def subject
    `ruby -e #{Shellwords.escape(load_path + program + flush_output)}`
  end

  let(:program) do
    <<-RUBY
      require 'ddtrace'
    RUBY
  end

  let(:load_path) do
    <<-RUBY
      # Ensure we load the working directory version of 'ddtrace' 
      lib = File.expand_path('../lib', __FILE__)
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
    RUBY
  end

  let(:flush_output) do
    <<-RUBY
      $stdout.flush
    RUBY
  end

  let(:iterations) { 30 }
  let(:benchmark) { iterations.times.reduce(0) { |acc, _| acc + subject.to_f } }
  let(:report_average) { benchmark / iterations }

  context 'timing' do
    let(:program) do
      <<-'RUBY'
      require 'benchmark'
      bm = Benchmark.measure do
        require 'ddtrace'
      end
      puts bm.real
      RUBY
    end

    it { puts "ddtrace gem load time: #{report_average}s" }
  end

  context 'memory' do
    let(:program) do
      <<-'RUBY'
      puts `ps -o rss= -p #{Process.pid}`.to_i
      require 'ddtrace'
      puts `ps -o rss= -p #{Process.pid}`.to_i
      RUBY
    end

    def subject
      output = super()

      measurements = output.split
      measurements[1].to_i - measurements[0].to_i
    end

    it { puts "ddtrace gem memory footprint: #{report_average} KiB" }
  end

  context 'detailed report' do
    before { skip('Detailed report are too verbose for CI') if ENV.key?('CI') }

    let(:program) do
      <<-'RUBY'
      require 'memory_profiler'
      # report = MemoryProfiler.report(ignore_files: /\.rbenv/) do
      report = MemoryProfiler.report do
        require 'ddtrace'
      end
      report.pretty_print
      RUBY
    end

    # Memory report with reference to each allocation site
    it 'memory report' do
      if PlatformHelpers.jruby? || Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
        skip("'benchmark/memory' not supported")
      end

      puts subject
    end
  end
end
