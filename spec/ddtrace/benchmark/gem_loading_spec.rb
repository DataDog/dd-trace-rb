if !PlatformHelpers.jruby? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
  require 'benchmark/memory'
  require 'memory_profiler'
end

require 'ddtrace'

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

  context 'timing' do
    let(:program) do
      <<-RUBY
      require 'benchmark'
      bm = Benchmark.measure do
        require 'ddtrace'
      end
      puts bm.real
      RUBY
    end

    it do
      # 0.15059919990599155
      # 0.1599752666739126

      i = 30
      total = i.times.reduce(0) { |acc, _| acc + subject.to_f }
      # puts total
      puts total.to_f / i
    end
  end

  context 'memory' do
    def memory_diff
      output = subject.split
      output[1].to_i - output[0].to_i
    end

    let(:program) do
      <<-RUBY
      puts `ps -o rss= -p \#{Process.pid}`.to_i
      require 'ddtrace'
      puts `ps -o rss= -p \#{Process.pid}`.to_i
      RUBY
    end

    it do
      i = 40
      total = i.times.reduce(0) { |acc, _| acc + memory_diff }
      puts "ddtrace memory footprint: #{total.to_f / i} KiB"
    end
  end

  context 'detailed report' do
    before { skip('Detailed report are too verbose for CI') if ENV.key?('CI') }

    let(:program) do
      <<-RUBY
      require 'memory_profiler'
      report = MemoryProfiler.report(ignore_files: /\.rbenv/) do
      # report = MemoryProfiler.report do
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

      # require 'rubygems'

      # Total allocated: 7751400 bytes (60499 objects)
      # Total retained:  1193126 bytes (9355 objects)
      #
      # 462874  net
      # 190131  json
      # 146647  msgpack-1.3.3
      # 140160  forwardable
      # 115063  x86_64-darwin18
      # 55740  pp
      # 21712  other
      # 17517  time
      # 8849  timeout
      # 7696  logger
      # 6160  securerandom
      # 5848  prettyprint
      # 3960  rubygems
      # 2104  ostruct
      # 1398  socket
      # 1295  date
      # 704  set

      # without contrib
      # Total allocated: 3888056 bytes (36556 objects)
      # Total retained:  666815 bytes (5757 objects)
      #
      # 462874  net
      # 190131  json
      # 146647  msgpack-1.3.3
      # 140160  forwardable
      # 115063  x86_64-darwin18
      # 55740  pp
      # 17804  other
      # 17517  time
      # 8849  timeout
      # 7696  logger
      # 6160  securerandom
      # 5848  prettyprint
      # 2104  ostruct
      # 1398  socket
      # 1295  date
      # 704  set


      # rails
      # 4633217  activesupport-6.0.3.1
      # 4039436  concurrent-ruby-1.1.6
      # 686514  psych
      # 627870  railties-6.0.3.1
      # 418979  openssl
      # 299574  x86_64-darwin18
      # 211013  cgi
      # 141791  i18n-1.8.2
      # 129198  ipaddr
      # 67180  yaml
      # 63861  json
      # 48973  tzinfo-1.2.7
      # 26817  actionpack-6.0.3.1
      # 24288  other
      # 21761  rack-2.2.2
      # 17477  time
      # 11460  timeout
      # 8152  logger
      # 7424  thread_safe-0.3.6
      # 6160  securerandom
      # 2536  set
      # 2104  ostruct
      # 1994  mutex_m
      # 1896  singleton
      # 1398  socket
      # 1345  digest
      # 1295  date
      # 1168  base64
      # 176  monitor
      # 120  bigdecimal



      # not in rails
      #
      # net
      # msgpack-1.3.3
      # forwardable
      # pp
      # prettyprint
      # rubygems

      # require 'prettyprint'

      puts subject
    end
  end
end
