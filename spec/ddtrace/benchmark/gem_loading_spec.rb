require 'spec_helper'

unless PlatformHelpers.jruby?
  require 'benchmark/memory'
  require 'memory_profiler'
end

RSpec.describe 'Gem loading' do
  def run_ruby
    `ruby -e #{Shellwords.escape(load_path + program + flush_output)}`
  end

  let(:program) do
    <<-RUBY
      require 'ddtrace'
    RUBY
  end

  let(:load_path) do
    # Ensure we load the working directory version of 'ddtrace'
    <<-RUBY
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
  let(:benchmark) { iterations.times.reduce(0) { |acc, _| acc + run_ruby.to_f } }
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

    def run_ruby
      output = super()

      before, after = output.split
      after.to_i - before.to_i
    end

    it { puts "ddtrace gem memory footprint: #{report_average} KiB" }
  end

  context 'detailed report' do
    before { skip('Detailed report are too verbose for CI') if ENV.key?('CI') }

    let(:program) do
      <<-'RUBY'
      require 'memory_profiler'

      # Exclude Ruby internals and gems from the report.
      # The memory consumed by them will still be captured
      # through 'require' statements and method calls present in ddtrace,
      # but their internals won't pollute the report output.
      ignore_files = %r{(.*/gems/[^/]*/lib/|/lib/ruby/\d)}

      report = MemoryProfiler.report(ignore_files: ignore_files) do
        require 'ddtrace'
      end

      report.pretty_print
      RUBY
    end

    # Memory report with reference to each allocation site
    it 'memory report' do
      skip("'benchmark/memory' not supported") if PlatformHelpers.jruby?

      puts run_ruby
    end
  end
end
