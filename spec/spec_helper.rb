$LOAD_PATH.unshift File.expand_path('..', __dir__)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

Thread.main.name = 'Thread.main' unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')

require 'pry'
require 'rspec/collection_matchers'
require 'rspec/wait'
require 'webmock/rspec'
require 'climate_control'

# Needed for calling JRuby.reference below
require 'jruby' if RUBY_ENGINE == 'jruby'

if (ENV['SKIP_SIMPLECOV'] != '1') && !RSpec.configuration.files_to_run.all? { |path| path.include?('/benchmark/') }
  # +SimpleCov.start+ must be invoked before any application code is loaded
  require 'simplecov'
  SimpleCov.start do
    formatter SimpleCov::Formatter::SimpleFormatter
  end
end

require 'datadog/core/encoding'
require 'datadog/tracing/tracer'
require 'datadog/tracing/span'

require 'support/core_helpers'
require 'support/faux_transport'
require 'support/faux_writer'
require 'support/loaded_gem'
require 'support/health_metric_helpers'
require 'support/log_helpers'
require 'support/network_helpers'
require 'support/object_space_helper'
require 'support/platform_helpers'
require 'support/span_helpers'
require 'support/spy_transport'
require 'support/synchronization_helpers'
require 'support/test_helpers'
require 'support/tracer_helpers'

require 'logger'

# require 'logger/period'

class Logger
  # Device used for logging messages.
  class LogDevice
    include Period

    attr_reader :dev
    attr_reader :filename
    include MonitorMixin

    def initialize(log = nil, shift_age: nil, shift_size: nil, shift_period_suffix: nil, binmode: false)
      @dev = @filename = @shift_age = @shift_size = @shift_period_suffix = nil
      @binmode = binmode
      mon_initialize
      set_dev(log)
      if @filename
        @shift_age = shift_age || 7
        @shift_size = shift_size || 1048576
        @shift_period_suffix = shift_period_suffix || '%Y%m%d'

        unless @shift_age.is_a?(Integer)
          base_time = @dev.respond_to?(:stat) ? @dev.stat.mtime : Time.now
          @next_rotate_time = next_rotate_time(base_time, @shift_age)
        end
      end
    end

    def write(message)
      begin
        synchronize do
          if @shift_age and @dev.respond_to?(:stat)
            begin
              check_shift_log
            rescue
              warn("log shifting failed. #{$!}")
            end
          end
          begin
            @dev.write(message)
          rescue
            puts '==== CALLER ===='
            puts caller
            puts '==== END ===='
            warn("log writing failed. #{$!}")
          end
        end
      rescue Exception => ignored
        puts '==== CALLER ===='
        puts caller
        puts '==== END ===='
        warn("log writing failed. #{ignored}")
      end
    end

    def close
      begin
        synchronize do
          @dev.close rescue nil
        end
      rescue Exception
        @dev.close rescue nil
      end
    end

    def reopen(log = nil)
      # reopen the same filename if no argument, do nothing for IO
      log ||= @filename if @filename
      if log
        synchronize do
          if @filename and @dev
            @dev.close rescue nil # close only file opened by Logger
            @filename = nil
          end
          set_dev(log)
        end
      end
      self
    end

    private

    def set_dev(log)
      if log.respond_to?(:write) and log.respond_to?(:close)
        @dev = log
        if log.respond_to?(:path)
          @filename = log.path
        end
      else
        @dev = open_logfile(log)
        @dev.sync = true
        @dev.binmode if @binmode
        @filename = log
      end
    end

    def open_logfile(filename)
      begin
        File.open(filename, (File::WRONLY | File::APPEND))
      rescue Errno::ENOENT
        create_logfile(filename)
      end
    end

    def create_logfile(filename)
      begin
        logdev = File.open(filename, (File::WRONLY | File::APPEND | File::CREAT | File::EXCL))
        logdev.flock(File::LOCK_EX)
        logdev.sync = true
        logdev.binmode if @binmode
        add_log_header(logdev)
        logdev.flock(File::LOCK_UN)
      rescue Errno::EEXIST
        # file is created by another process
        logdev = open_logfile(filename)
        logdev.sync = true
      end
      logdev
    end

    def add_log_header(file)
      file.write(
        "# Logfile created on %s by %s\n" % [Time.now.to_s, Logger::ProgName]
      ) if file.size == 0
    end

    def check_shift_log
      if @shift_age.is_a?(Integer)
        # Note: always returns false if '0'.
        if @filename && (@shift_age > 0) && (@dev.stat.size > @shift_size)
          lock_shift_log { shift_log_age }
        end
      else
        now = Time.now
        if now >= @next_rotate_time
          @next_rotate_time = next_rotate_time(now, @shift_age)
          lock_shift_log { shift_log_period(previous_period_end(now, @shift_age)) }
        end
      end
    end

    if /mswin|mingw|cygwin/ =~ RbConfig::CONFIG['host_os']
      def lock_shift_log
        yield
      end
    else
      def lock_shift_log
        retry_limit = 8
        retry_sleep = 0.1
        begin
          File.open(@filename, File::WRONLY | File::APPEND) do |lock|
            lock.flock(File::LOCK_EX) # inter-process locking. will be unlocked at closing file
            if File.identical?(@filename, lock) and File.identical?(lock, @dev)
              yield # log shifting
            else
              # log shifted by another process (i-node before locking and i-node after locking are different)
              @dev.close rescue nil
              @dev = open_logfile(@filename)
              @dev.sync = true
            end
          end
        rescue Errno::ENOENT
          # @filename file would not exist right after #rename and before #create_logfile
          if retry_limit <= 0
            warn("log rotation inter-process lock failed. #{$!}")
          else
            sleep retry_sleep
            retry_limit -= 1
            retry_sleep *= 2
            retry
          end
        end
      rescue
        warn("log rotation inter-process lock failed. #{$!}")
      end
    end

    def shift_log_age
      (@shift_age-3).downto(0) do |i|
        if FileTest.exist?("#{@filename}.#{i}")
          File.rename("#{@filename}.#{i}", "#{@filename}.#{i+1}")
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", "#{@filename}.0")
      @dev = create_logfile(@filename)
      return true
    end

    def shift_log_period(period_end)
      suffix = period_end.strftime(@shift_period_suffix)
      age_file = "#{@filename}.#{suffix}"
      if FileTest.exist?(age_file)
        # try to avoid filename crash caused by Timestamp change.
        idx = 0
        # .99 can be overridden; avoid too much file search with 'loop do'
        while idx < 100
          idx += 1
          age_file = "#{@filename}.#{suffix}.#{idx}"
          break unless FileTest.exist?(age_file)
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", age_file)
      @dev = create_logfile(@filename)
      return true
    end
  end
end


begin
  # Ignore interpreter warnings from external libraries
  require 'warning'

  # Ignore warnings in Gem dependencies
  Gem.path.each do |path|
    Warning.ignore([:method_redefined, :not_reached, :unused_var, :arg_prefix], path)
    Warning.ignore(/circular require considered harmful/, path)
  end
rescue LoadError
  puts 'warning suppressing gem not available, external library warnings will be displayed'
end

WebMock.allow_net_connect!
WebMock.disable!

RSpec.configure do |config|
  config.include CoreHelpers
  config.include HealthMetricHelpers
  config.include LogHelpers
  config.include NetworkHelpers
  config.include LoadedGem
  config.extend  LoadedGem::Helpers
  config.include LoadedGem::Helpers
  config.include SpanHelpers
  config.include SynchronizationHelpers
  config.include TracerHelpers
  config.include TestHelpers::RSpec::Integration, :integration

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  config.example_status_persistence_file_path = 'tmp/example_status_persistence'

  # rspec-wait configuration
  config.wait_timeout = 5 # default timeout for `wait_for(...)`, in seconds
  config.wait_delay = 0.01 # default retry delay for `wait_for(...)`, in seconds

  if config.files_to_run.one?
    # Use the documentation formatter for detailed output,
    # unless a formatter has already been configured
    # (e.g. via a command-line flag).
    config.default_formatter = 'doc'
  end

  # Check for leaky test resources.
  #
  # Execute this after the test has finished
  # teardown and mock verifications.
  #
  # Changing this to `config.after(:each)` would
  # put this code inside the test scope, interfering
  # with the test execution.
  #
  # rubocop:disable Style/GlobalVars
  config.around do |example|
    example.run.tap do
      # Stop reporting on background thread leaks after too many
      # successive failures. The output is very verbose and, at that point,
      # it's better to work on fixing the very first occurrences.
      $background_thread_leak_reports ||= 0
      if $background_thread_leak_reports >= 3
        unless $background_thread_leak_warned ||= false
          warn RSpec::Core::Formatters::ConsoleCodes.wrap(
            "Too many leaky thread reports! Suppressing further reports.\n" \
            'Consider addressing the previously reported leaks before proceeding.',
            :red
          )

          $background_thread_leak_warned = true
        end

        next
      end

      # Exclude acceptable background threads
      background_threads = Thread.list.reject do |t|
        group_name = t.group.instance_variable_get(:@group_name) if t.group.instance_variable_defined?(:@group_name)
        backtrace = t.backtrace || []

        # Current thread
        t == Thread.current ||
          # Thread has shut down, but we caught it right as it was still alive
          !t.alive? ||
          # Long-lived Timeout thread created by `Timeout.create_timeout_thread`.
          (t.respond_to?(:name) && t.name == 'Timeout stdlib thread') ||
          # JRuby: Long-lived Timeout thread created by `Timeout.create_timeout_thread`.
          t == Timeout.instance_exec { @timeout_thread if defined?(@timeout_thread) } ||
          # Internal JRuby thread
          defined?(JRuby) && JRuby.reference(t).native_thread.name == 'Finalizer' ||
          # WEBrick singleton thread for handling timeouts
          backtrace.find { |b| b.include?('/webrick/utils.rb') } ||
          # WEBrick server thread
          t[:WEBrickSocket] ||
          # Rails connection reaper
          backtrace.find { |b| b.include?('lib/active_record/connection_adapters/abstract/connection_pool.rb') } ||
          # Ruby JetBrains debugger
          (t.class.name && t.class.name.include?('DebugThread')) ||
          # Categorized as a known leaky thread
          !group_name.nil? ||
          # Internal TruffleRuby thread, defined in
          # https://github.com/oracle/truffleruby/blob/02f568556ca4dd9056b0114b750ab848ac52943b/src/main/java/org/truffleruby/core/ReferenceProcessingService.java#L221
          RUBY_ENGINE == 'truffleruby' && t.to_s.include?('Ruby-reference-processor')
      end

      unless background_threads.empty?
        # TODO: Temporarily disabled for `spec/ddtrace/workers`
        # was meaningful changes are required to address clean
        # teardown in those tests.
        # They currently flood the output, making our test
        # suite output unreadable.
        if example.file_path.start_with?(
          './spec/datadog/core/workers/',
          './spec/ddtrace/workers/'
        )
          puts # Add newline so we get better output when the progress formatter is being used
          RSpec.warning("FIXME: #{example.file_path}:#{example.metadata[:line_number]} is leaking threads")
          next
        end

        info = background_threads.each_with_index.flat_map do |t, idx|
          backtrace = t.backtrace
          if backtrace.nil? && t.alive? # Maybe the thread hasn't run yet? Let's give it a second chance
            Thread.pass
            backtrace = t.backtrace
          end
          if backtrace.nil? || backtrace.empty?
            backtrace =
              if t.alive?
                ['(Not available. Possibly a native thread.)']
              else
                ['(Thread finished before we could collect a backtrace)']
              end
          end

          caller = t.instance_variable_get(:@caller) || ['(Not available. Possibly a native thread.)']
          [
            "#{idx + 1}: #{t} (#{t.class.name})",
            'Thread Creation Site:',
            caller.map { |l| "\t#{l}" }.join("\n"),
            'Thread Backtrace:',
            backtrace.map { |l| "\t#{l}" }.join("\n"),
            "\n"
          ]
        end.join("\n")

        # Warn about leakly thread
        warn RSpec::Core::Formatters::ConsoleCodes.wrap(
          "\nSpec leaked #{background_threads.size} threads in \"#{example.full_description}\".\n" \
          "Ensure all threads are terminated when test finishes.\n" \
          "For help fixing this issue, see \"Ensuring tests don't leak resources\" in docs/DevelopmentGuide.md.\n" \
          "\n" \
          "#{info}",
          :yellow
        )

        $background_thread_leak_reports += 1
      end
    end
  end
  # rubocop:enable Style/GlobalVars

  # Closes the global testing tracer.
  #
  # Execute this after the test has finished
  # teardown and mock verifications.
  #
  # Changing this to `config.after(:each)` would
  # put this code inside the test scope, interfering
  # with the test execution.
  config.around do |example|
    example.run.tap do
      tracer_shutdown!
    end
  end
end

# Stores the caller thread backtrace,
# To allow for leaky threads to be traced
# back to their creation point.
module DatadogThreadDebugger
  # DEV: we have to use an explicit `block`, argument
  # instead of the implicit `yield` call, as calling
  # `yield` here crashes the Ruby VM in Ruby < 2.2.
  def initialize(*args, &block)
    @caller = caller
    wrapped = lambda do |*thread_args|
      block.call(*thread_args) # rubocop:disable Performance/RedundantBlockCall
    end
    wrapped.send(:ruby2_keywords) if wrapped.respond_to?(:ruby2_keywords, true)

    super(*args, &wrapped)
  end

  ruby2_keywords :initialize if respond_to?(:ruby2_keywords, true)
end

Thread.prepend(DatadogThreadDebugger)

require 'spec/support/thread_helpers'
# Enforce test time limit, to allow us to debug why some test runs get stuck in CI
if ENV.key?('CI')
  ThreadHelpers.with_leaky_thread_creation('Deadline thread') do
    Thread.new do
      Thread.current.name = 'spec_helper.rb CI debugging Deadline thread' unless RUBY_VERSION.start_with?('2.1.', '2.2.')

      sleep_time = 30 * 60 # 30 minutes
      sleep(sleep_time)

      warn "Test too longer than #{sleep_time}s to finish, aborting test run."
      warn 'Stack trace of all running threads:'

      Thread.list.select { |t| t.alive? && t != Thread.current }.each_with_index.map do |t, idx|
        backtrace = t.backtrace
        backtrace = ['(Not available)'] if backtrace.nil? || backtrace.empty?

        msg = "#{idx}: #{t} (#{t.class.name})",
              'Thread Backtrace:',
              backtrace.map { |l| "\t#{l}" }.join("\n"),
              "\n"

        warn(msg) rescue puts(msg)
      end

      Kernel.exit(1)
    end
  end
end

# Helper matchers
RSpec::Matchers.define_negated_matcher :not_be, :be

# The Ruby Timeout class uses a long-lived class-level thread that is never terminated.
# Creating it early here ensures tests that tests that check for leaking threads are not
# triggered by the creation of this thread.
#
# This has to be one once for the lifetime of this process, and was introduced in Ruby 3.1.
# Before 3.1, a thread was created and destroyed on every Timeout#timeout call.
Timeout.ensure_timeout_thread_created if Timeout.respond_to?(:ensure_timeout_thread_created)
