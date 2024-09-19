require 'bundler/gem_tasks'
require 'datadog/version'
require 'rubocop/rake_task' if Gem.loaded_specs.key? 'rubocop'
require 'standard/rake' if Gem.loaded_specs.key? 'standard'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'os'
if Gem.loaded_specs.key? 'ruby_memcheck'
  require 'ruby_memcheck'
  require 'ruby_memcheck/rspec/rake_task'

  RubyMemcheck.config(
    # If there's an error, print the suppression for that error, to allow us to easily skip such an error if it's
    # a false-positive / something in the VM we can't fix.
    valgrind_generate_suppressions: true,
    # This feature provides better quality data -- I couldn't get good output out of ruby_memcheck without it.
    use_only_ruby_free_at_exit: true,
  )
end

Dir.glob('tasks/*.rake').each { |r| import r }

TEST_METADATA = eval(File.read('Matrixfile')).freeze # rubocop:disable Security/Eval

namespace :test do
  desc 'Run all tests'
  task all: TEST_METADATA.map { |k, _| "test:#{k}" }

  ruby_version = RUBY_VERSION[0..2]

  major, minor, = if defined?(RUBY_ENGINE_VERSION)
                    Gem::Version.new(RUBY_ENGINE_VERSION).segments
                  else
                    # For Ruby < 2.3
                    Gem::Version.new(RUBY_VERSION).segments
                  end

  ruby_runtime = "#{RUBY_ENGINE}-#{major}.#{minor}"

  TEST_METADATA.each do |key, spec_metadata|
    spec_task = "spec:#{key}"

    desc "Run #{spec_task} tests"
    task key, [:task_args] do |_, args|
      spec_arguments = args.task_args

      candidates = spec_metadata.select do |appraisal_group, rubies|
        if RUBY_PLATFORM == 'java'
          # Rails 4.x is not supported on JRuby 9.2 (which is RUBY_VERSION 2.5)
          next false if ruby_runtime == 'jruby-9.2' && appraisal_group.start_with?('rails4')

          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      candidates.each do |appraisal_group, _|
        command = if appraisal_group.empty?
                    "bundle exec rake #{spec_task}"
                  else
                    "bundle exec appraisal #{ruby_runtime}-#{appraisal_group} rake #{spec_task}"
                  end

        command += "'[#{spec_arguments}]'" if spec_arguments

        total_executors = ENV.key?('CIRCLE_NODE_TOTAL') ? ENV['CIRCLE_NODE_TOTAL'].to_i : nil
        current_executor = ENV.key?('CIRCLE_NODE_INDEX') ? ENV['CIRCLE_NODE_INDEX'].to_i : nil

        if total_executors && current_executor && total_executors > 1
          @execution_count ||= 0
          @execution_count += 1
          sh(command) if @execution_count % total_executors == current_executor
        else
          sh(command)
        end
      end
    end
  end
end

desc 'Run RSpec'
# rubocop:disable Metrics/BlockLength
namespace :spec do
  task all: [:main, :benchmark,
             :graphql, :graphql_unified_trace_patcher, :graphql_trace_patcher, :graphql_tracing_patcher,
             :rails, :railsredis, :railsredis_activesupport, :railsactivejob,
             :elasticsearch, :http, :redis, :sidekiq, :sinatra, :hanami, :hanami_autoinstrument,
             :profiling, :crashtracking]

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:main) do |t, args|
    t.pattern = 'spec/**/*_spec.rb'
    t.exclude_pattern = 'spec/**/{contrib,benchmark,redis,auto_instrument,opentelemetry,profiling,crashtracking}/**/*_spec.rb,'\
                        ' spec/**/{auto_instrument,opentelemetry}_spec.rb, spec/datadog/gem_packaging_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:benchmark) do |t, args|
    t.pattern = 'spec/datadog/benchmark/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:graphql) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/graphql/**/*_spec.rb'
    t.exclude_pattern = 'spec/datadog/tracing/contrib/graphql/{unified_trace,trace,tracing}_patcher_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:graphql_unified_trace_patcher) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/graphql/unified_trace_patcher_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:graphql_trace_patcher) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/graphql/trace_patcher_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:graphql_tracing_patcher) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/graphql/tracing_patcher_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:opentelemetry) do |t, args|
    t.pattern = 'spec/datadog/opentelemetry/**/*_spec.rb,spec/datadog/opentelemetry_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:rails) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*_spec.rb'
    t.exclude_pattern = 'spec/datadog/tracing/contrib/rails/**/*{active_job,disable_env,redis_cache,auto_instrument,'\
                        'semantic_logger}*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:railsredis) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:railsredis_activesupport) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')

    # Flag used to tell specs the expected configuration (so that they break if they're not being setup correctly)
    ENV['EXPECT_RAILS_ACTIVESUPPORT'] = 'true'
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:railsactivejob) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*active_job*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:railsdisableenv) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*disable_env*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:railsautoinstrument) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*auto_instrument*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:hanami) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/hanami/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:hanami_autoinstrument) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/hanami/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')

    ENV['TEST_AUTO_INSTRUMENT'] = 'true'
  end

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:autoinstrument) do |t, args|
    t.pattern = 'spec/datadog/auto_instrument_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:yjit) do |t, args|
    t.pattern = 'spec/datadog/core/runtime/metrics_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  # rails_semantic_logger is the dog at the dog park that doesnt play nicely with other
  # logging gems, aka it tries to bite/monkeypatch them, so we have to put it in its own appraisal and rake task
  # in order to isolate its effects for rails logs auto injection
  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:railssemanticlogger) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*rails_semantic_logger*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  # rubocop:disable Style/MultilineBlockChain
  RSpec::Core::RakeTask.new(:crashtracking) do |t, args|
    t.pattern = 'spec/datadog/core/crashtracking/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end.tap do |t|
    Rake::Task[t.name].enhance(["compile:libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}"])
  end
  # rubocop:enable Style/MultilineBlockChain

  desc '' # "Explicitly hiding from `rake -T`"
  RSpec::Core::RakeTask.new(:contrib) do |t, args|
    contrib_paths = [
      '*',
      'configuration/*',
      'configuration/resolvers/*',
      'registry/*',
      'propagation/**/*',
    ].join(',')

    t.pattern = "spec/**/contrib/{#{contrib_paths}}_spec.rb"
    t.rspec_opts = args.to_a.join(' ')
  end

  # Datadog Tracing integrations
  [
    :action_cable,
    :action_mailer,
    :action_pack,
    :action_view,
    :active_model_serializers,
    :active_record,
    :active_support,
    :aws,
    :concurrent_ruby,
    :dalli,
    :delayed_job,
    :elasticsearch,
    :ethon,
    :excon,
    :faraday,
    :grape,
    :grpc,
    :http,
    :httpclient,
    :httprb,
    :kafka,
    :lograge,
    :mongodb,
    :mysql2,
    :opensearch,
    :pg,
    :presto,
    :que,
    :racecar,
    :rack,
    :rake,
    :redis,
    :resque,
    :roda,
    :rest_client,
    :semantic_logger,
    :sequel,
    :shoryuken,
    :sidekiq,
    :sinatra,
    :sneakers,
    :stripe,
    :sucker_punch,
    :suite,
    :trilogy
  ].each do |contrib|
    desc '' # "Explicitly hiding from `rake -T`"
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/tracing/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end

  namespace :appsec do
    task all: [:main, :rack, :rails, :sinatra, :devise, :graphql]

    # Datadog AppSec main specs
    desc '' # "Explicitly hiding from `rake -T`"
    RSpec::Core::RakeTask.new(:main) do |t, args|
      t.pattern = 'spec/datadog/appsec/**/*_spec.rb'
      t.exclude_pattern = 'spec/datadog/appsec/**/{contrib,auto_instrument}/**/*_spec.rb,'\
                          ' spec/datadog/appsec/**/{auto_instrument,autoload}_spec.rb'
      t.rspec_opts = args.to_a.join(' ')
    end

    # Datadog AppSec integrations
    [
      :rack,
      :sinatra,
      :rails,
      :devise,
      :graphql,
    ].each do |contrib|
      desc '' # "Explicitly hiding from `rake -T`"
      RSpec::Core::RakeTask.new(contrib) do |t, args|
        t.pattern = "spec/datadog/appsec/contrib/#{contrib}/**/*_spec.rb"
        t.rspec_opts = args.to_a.join(' ')
      end
    end
  end

  task appsec: [:'appsec:all']

  namespace :profiling do
    task all: [:main, :ractors]

    task :compile_native_extensions do
      # "bundle exec rake compile" currently only works on MRI Ruby on Linux
      if RUBY_ENGINE == 'ruby' && OS.linux? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.3.0')
        Rake::Task[:clean].invoke
        Rake::Task[:compile].invoke
      end
    end

    # Datadog Profiling main specs without Ractor creation
    # NOTE: Ractor creation will transition the entire Ruby VM into multi-ractor mode. This cannot be undone
    #       and, as such, may introduce side-effects between tests and make them flaky depending on order of
    #       execution. By splitting in two separate suites, the side-effect impact should be mitigated as
    #       the non-ractor VM will never trigger the transition into multi-ractor mode.
    desc '' # "Explicitly hiding from `rake -T`"
    RSpec::Core::RakeTask.new(:main) do |t, args|
      t.pattern = 'spec/datadog/profiling/**/*_spec.rb,spec/datadog/profiling_spec.rb'
      t.rspec_opts = [*args.to_a, '-t ~ractors'].join(' ')
    end

    desc '' # "Explicitly hiding from `rake -T`"
    RSpec::Core::RakeTask.new(:ractors) do |t, args|
      t.pattern = 'spec/datadog/profiling/**/*_spec.rb'
      t.rspec_opts = [*args.to_a, '-t ractors'].join(' ')
    end

    desc 'Run spec:profiling:main tests with memory leak checking'
    if Gem.loaded_specs.key?('ruby_memcheck')
      RubyMemcheck::RSpec::RakeTask.new(:memcheck) do |t, args|
        t.pattern = 'spec/datadog/profiling/**/*_spec.rb,spec/datadog/profiling_spec.rb'
        # Some of our specs use multi-threading + busy looping, or multiple processes, or are just really really slow.
        # We skip running these when running under valgrind.
        # (As a reminder, by default valgrind simulates a sequential/single-threaded execution).
        #
        # @ivoanjo: I previously tried https://github.com/Shopify/ruby_memcheck/issues/51 but in some cases valgrind
        # would give incomplete output, causing a "FATAL: Premature end of data in tag valgrindoutput line 3" error in
        # ruby_memcheck. I did not figure out why exactly.
        t.rspec_opts = [*args.to_a, '-t ~ractors -t ~memcheck_valgrind_skip'].join(' ')
      end
    else
      task :memcheck do
        raise 'Memcheck requires the ruby_memcheck gem to be installed'
      end
    end

    # Make sure each profiling test suite has a dependency on compiled native extensions
    Rake::Task[:all].prerequisite_tasks.each { |t| t.enhance([:compile_native_extensions]) }
  end

  task profiling: [:'profiling:all']
end

if defined?(RuboCop::RakeTask)
  RuboCop::RakeTask.new(:rubocop) do |_t|
  end
end

# Jobs are parallelized if running in CI.
desc 'CI task; it runs all tests for current version of Ruby'
task ci: 'test:all'

namespace :coverage do
  # Generates one global report for all tracer tests
  task :report do
    require 'simplecov'

    resultset_files = Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/.resultset.json"] +
      Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/**/.resultset.json"]

    SimpleCov.collate resultset_files do
      coverage_dir "#{ENV.fetch('COVERAGE_DIR', 'coverage')}/report"
      if ENV['CI'] == 'true'
        require 'simplecov-cobertura'
        formatter SimpleCov::Formatter::MultiFormatter.new(
          [SimpleCov::Formatter::HTMLFormatter,
           SimpleCov::Formatter::CoberturaFormatter] # Used by codecov
        )
      else
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end
  end

  # Generates one report for each Ruby version
  task :report_per_ruby_version do
    require 'simplecov'

    versions = Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/*"].map { |f| File.basename(f) }
    versions.map do |version|
      puts "Generating report for: #{version}"
      SimpleCov.collate Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/#{version}/**/.resultset.json"] do
        coverage_dir "#{ENV.fetch('COVERAGE_DIR', 'coverage')}/report/versions/#{version}"
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end
  end
end

namespace :changelog do
  task :format do
    require 'pimpmychangelog'

    PimpMyChangelog::CLI.run!
  end
end

NATIVE_EXTS = [
  Rake::ExtensionTask.new("datadog_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
    ext.ext_dir = 'ext/datadog_profiling_native_extension'
  end,

  Rake::ExtensionTask.new("datadog_profiling_loader.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
    ext.ext_dir = 'ext/datadog_profiling_loader'
  end,

  Rake::ExtensionTask.new("libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}") do |ext|
    ext.ext_dir = 'ext/libdatadog_api'
  end
].freeze

NATIVE_CLEAN = ::Rake::FileList[]
namespace :native_dev do
  compile_commands_tasks = NATIVE_EXTS.map do |ext|
    tmp_dir_dd_native_dev = "#{ext.tmp_dir}/dd_native_dev"
    directory tmp_dir_dd_native_dev
    NATIVE_CLEAN << tmp_dir_dd_native_dev

    compile_commands_task = file "#{ext.ext_dir}/compile_commands.json" => [tmp_dir_dd_native_dev] do |t|
      puts "Generating #{t.name}"
      root_dir = Dir.pwd
      cmd = ext.make_makefile_cmd(root_dir, tmp_dir_dd_native_dev, "#{ext.ext_dir}/#{ext.config_script}", nil)
      abs_ext_dir = (Pathname.new(root_dir) + ext.ext_dir).realpath
      chdir tmp_dir_dd_native_dev do
        sh(*cmd)
        sh('make clean; bear -- make; make clean')
        cp('compile_commands.json', "#{abs_ext_dir}/compile_commands.json")
      end
    end

    NATIVE_CLEAN << compile_commands_task.name

    compile_commands_task
  end

  desc 'Setup dev environment for native extensions.'
  task setup: compile_commands_tasks

  CLEAN.concat(NATIVE_CLEAN)
end

desc 'Runs rubocop + main test suite'
task default: ['rubocop', 'standard', 'typecheck', 'spec:main']

desc 'Runs the default task in parallel'
multitask fastdefault: ['rubocop', 'standard', 'typecheck', 'spec:main']
