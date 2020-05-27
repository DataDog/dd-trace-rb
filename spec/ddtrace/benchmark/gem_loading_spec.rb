if !PlatformHelpers.jruby? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
  require 'benchmark/memory'
  require 'memory_profiler'
end

RSpec.describe "Gem loading" do
  subject { `ruby -e #{Shellwords.escape(program)}` }

  let(:program) do
    <<-'RUBY'
      # Ensure we load the working directory version of 'ddtrace' 
      lib = File.expand_path('../lib', __FILE__)
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

      require 'memory_profiler'

      puts `ps -o rss= -p #{Process.pid}`.to_i

      report = MemoryProfiler.report do
        require 'ddtrace'
      end
      report.pretty_print
      # require 'ddtrace'

      puts `ps -o rss= -p #{Process.pid}`.to_i

      $stdout.flush
    RUBY
  end

  let(:memory_before) { subject.split[0].to_i }
  let(:memory_after) { subject.split[1].to_i }
  let(:memory_diff) { memory_after - memory_before }

  it 'loads gem' do
    puts "ddtrace memory footprint: #{memory_diff} KiB"
  end

  context 'detailed report' do
    before { skip('Detailed report are too verbose for CI') if ENV.key?('CI') }

    # Memory report with reference to each allocation site
    it 'memory report' do
      if PlatformHelpers.jruby? || Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
        skip("'benchmark/memory' not supported")
      end

      puts subject
    end
  end
end
