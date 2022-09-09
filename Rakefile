require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task' if Gem.loaded_specs.key? 'rubocop'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'appraisal'
require 'yard'
require 'os'

Dir.glob('tasks/*.rake').each { |r| import r }

desc 'Run RSpec'
# rubocop:disable Metrics/BlockLength
namespace :spec do
  task all: [:main, :benchmark,
             :rails, :railsredis, :railsredis_activesupport, :railsactivejob,
             :elasticsearch, :http, :redis, :sidekiq, :sinatra, :hanami, :hanami_autoinstrument]

  RSpec::Core::RakeTask.new(:main) do |t, args|
    t.pattern = 'spec/**/*_spec.rb'
    t.exclude_pattern = 'spec/**/{contrib,benchmark,redis,opentracer,auto_instrument}/**/*_spec.rb,'\
                        ' spec/**/auto_instrument_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end
  if RUBY_ENGINE == 'ruby' && OS.linux? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.2.0')
    # "bundle exec rake compile" currently only works on MRI Ruby on Linux
    Rake::Task[:main].enhance([:compile])
  end

  RSpec::Core::RakeTask.new(:benchmark) do |t, args|
    t.pattern = 'spec/ddtrace/benchmark/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:opentracer) do |t, args|
    t.pattern = 'spec/datadog/opentracer/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:rails) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*_spec.rb'
    t.exclude_pattern = 'spec/datadog/tracing/contrib/rails/**/*{active_job,disable_env,redis_cache,auto_instrument,'\
                        'semantic_logger}*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsredis) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsredis_activesupport) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')

    # Flag used to tell specs the expected configuration (so that they break if they're not being setup correctly)
    ENV['EXPECT_RAILS_ACTIVESUPPORT'] = 'true'
  end

  RSpec::Core::RakeTask.new(:railsactivejob) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*active_job*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsdisableenv) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*disable_env*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsautoinstrument) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*auto_instrument*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:hanami) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/hanami/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:hanami_autoinstrument) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/hanami/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')

    ENV['TEST_AUTO_INSTRUMENT'] = 'true'
  end

  RSpec::Core::RakeTask.new(:autoinstrument) do |t, args|
    t.pattern = 'spec/ddtrace/auto_instrument_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  # rails_semantic_logger is the dog at the dog park that doesnt play nicely with other
  # logging gems, aka it tries to bite/monkeypatch them, so we have to put it in its own appraisal and rake task
  # in order to isolate its effects for rails logs auto injection
  RSpec::Core::RakeTask.new(:railssemanticlogger) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*rails_semantic_logger*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:contrib) do |t, args|
    contrib_paths = [
      'analytics',
      'configurable',
      'configuration/*',
      'configuration/resolvers/*',
      'extensions',
      'integration',
      'patchable',
      'patcher',
      'registerable',
      'registry',
      'registry/*'
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
    :graphql,
    :grpc,
    :http,
    :httpclient,
    :httprb,
    :kafka,
    :lograge,
    :mongodb,
    :mysql2,
    :pg,
    :presto,
    :qless,
    :que,
    :racecar,
    :rack,
    :rake,
    :redis,
    :resque,
    :rest_client,
    :semantic_logger,
    :sequel,
    :shoryuken,
    :sidekiq,
    :sinatra,
    :sneakers,
    :sucker_punch,
    :suite
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/tracing/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end

  # Datadog CI integrations
  [
    :cucumber,
    :rspec
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/ci/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end

  namespace :appsec do
    task all: [:main]

    # Datadog AppSec main specs
    RSpec::Core::RakeTask.new(:main) do |t, args|
      t.pattern = 'spec/datadog/appsec/**/*_spec.rb'
      t.exclude_pattern = 'spec/datadog/appsec/**/{contrib,auto_instrument}/**/*_spec.rb,'\
                          ' spec/datadog/appsec/**/{auto_instrument,autoload}_spec.rb'
      t.rspec_opts = args.to_a.join(' ')
    end
  end

  task appsec: [:'appsec:all']
end

if defined?(RuboCop::RakeTask)
  RuboCop::RakeTask.new(:rubocop) do |_t|
  end
end

YARD::Rake::YardocTask.new(:docs) do |t|
  # Options defined in `.yardopts` are read first, then merged with
  # options defined here.
  #
  # It's recommended to define options in `.yardopts` instead of here,
  # as `.yardopts` can be read by external YARD tools, like the
  # hot-reload YARD server `yard server --reload`.

  t.options += ['--title', "ddtrace #{DDTrace::VERSION::STRING} documentation"]
end

# Deploy tasks
S3_BUCKET = 'gems.datadoghq.com'.freeze
S3_DIR = ENV['S3_DIR']

desc 'release the docs website'
task :'release:docs' => :docs do
  raise 'Missing environment variable S3_DIR' if !S3_DIR || S3_DIR.empty?

  sh "aws s3 cp --recursive doc/ s3://#{S3_BUCKET}/#{S3_DIR}/docs/"
end

# Declare a command for execution.
# Jobs are parallelized if running in CI.
def declare(rubies_to_command)
  rubies, command = rubies_to_command.first

  return unless rubies.include?("✅ #{RUBY_VERSION[0..2]}")
  return if RUBY_PLATFORM == 'java' && rubies.include?('❌ jruby')

  total_executors = ENV.key?('CIRCLE_NODE_TOTAL') ? ENV['CIRCLE_NODE_TOTAL'].to_i : nil
  current_executor = ENV.key?('CIRCLE_NODE_INDEX') ? ENV['CIRCLE_NODE_INDEX'].to_i : nil

  ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
                   "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
                 else
                   "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
                 end

  command.sub!(/^bundle exec appraisal /, "bundle exec appraisal #{ruby_runtime}-")

  if total_executors && current_executor && total_executors > 1
    @execution_count ||= 0
    @execution_count += 1
    sh(command) if @execution_count % total_executors == current_executor
  else
    sh(command)
  end
end

desc 'CI task; it runs all tests for current version of Ruby'
task :ci do
  # ADD NEW RUBIES HERE

  # Main library
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec rake spec:main'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal core-old rake spec:main'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec rake spec:appsec:main'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec rake spec:contrib'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec rake spec:opentracer'

  # Contrib specs
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:action_pack'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:action_view'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:active_model_serializers'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:active_record'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:active_support'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:autoinstrument'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:aws'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:concurrent_ruby'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:cucumber'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:dalli'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:delayed_job'
  declare '✅ 2.1 / ✅ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:elasticsearch' # 2.3 and 2.4 are tested via contrib-old
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:ethon'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:excon'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:faraday'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:grape'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:graphql'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ❌ jruby' => 'bundle exec appraisal contrib rake spec:grpc' # disabled on JRuby, protobuf not supported
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:http'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:httpclient'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:httprb'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:kafka'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:lograge' # disabled on 3.0 as lograge nested dependancy thor ~> 1.0 conflicts w/qless dependancy thor ~> 0.19.1
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:mongodb'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ❌ jruby' => 'bundle exec appraisal contrib rake spec:mysql2' # disabled on JRuby, built-in jdbc is used instead
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ❌ jruby' => 'bundle exec appraisal contrib rake spec:pg'
  declare '✅ 2.1 / ✅ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ jruby' => 'bundle exec appraisal contrib rake spec:presto'
  declare '❌ 2.1 / ✅ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:qless'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:que'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:racecar' # disabled on 3.0 pending release of our fix: https://github.com/appsignal/rdkafka-ruby/pull/144
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:rack'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:rake'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:redis'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:resque'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:rest_client'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:rspec'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:semantic_logger'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:sequel'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:shoryuken'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:sidekiq'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:sinatra'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:sneakers'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:sucker_punch'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib rake spec:suite'

  # Contrib specs with old gem versions
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib-old rake spec:dalli'
  declare '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib-old rake spec:elasticsearch'
  declare '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib-old rake spec:faraday'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib-old rake spec:graphql'
  declare '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal contrib-old rake spec:presto'

  # Rails specs
  # On Ruby 2.4 and 2.5, we only test Rails 5+ because older versions require Bundler < 2.0
  declare '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-mysql2 rake spec:active_record'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-mysql2 rake spec:rails'
  declare '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres rake spec:action_pack'
  declare '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres rake spec:action_view'
  declare '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres rake spec:active_support'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres rake spec:rails'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres rake spec:railsautoinstrument'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis_activesupport'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-mysql2 rake spec:rails'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-postgres rake spec:rails'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-postgres rake spec:railsautoinstrument'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis_activesupport'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-postgres-sidekiq rake spec:railsactivejob'
  declare '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails4-semantic-logger rake spec:railssemanticlogger'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-mysql2 rake spec:action_cable'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-mysql2 rake spec:action_mailer'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-mysql2 rake spec:rails'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-postgres rake spec:rails'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-postgres rake spec:railsautoinstrument'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis_activesupport'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
  declare '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails5-semantic-logger rake spec:railssemanticlogger'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-mysql2 rake spec:action_cable'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-mysql2 rake spec:action_mailer'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-mysql2 rake spec:rails'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-postgres rake spec:rails'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-postgres rake spec:railsautoinstrument'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis_activesupport'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails6-semantic-logger rake spec:railssemanticlogger'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-mysql2 rake spec:action_cable'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-mysql2 rake spec:action_mailer'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ❌ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-mysql2 rake spec:rails'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-postgres rake spec:rails'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-postgres rake spec:railsdisableenv'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-postgres-redis rake spec:railsredis'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-postgres-sidekiq rake spec:railsactivejob'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal rails61-semantic-logger rake spec:railssemanticlogger'

  # explicitly test Hanami compatability
  declare '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ jruby' => 'bundle exec appraisal hanami-1 rake spec:hanami'

  # explicitly test resque-2x compatability
  declare '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal resque2-redis3 rake spec:resque'
  declare '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal resque2-redis4 rake spec:resque'

  # explicitly test cucumber compatibility
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal cucumber3 rake spec:cucumber'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal cucumber4 rake spec:cucumber'
  declare '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ jruby' => 'bundle exec appraisal cucumber5 rake spec:cucumber'
end

namespace :coverage do
  # Generates one global report for all tracer tests
  task :report do
    require 'simplecov'

    resultset_files = Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/.resultset.json"] +
      Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/**/.resultset.json"]

    SimpleCov.collate resultset_files do
      coverage_dir "#{ENV.fetch('COVERAGE_DIR', 'coverage')}/report"
      if ENV['CI'] == 'true'
        require 'codecov'
        formatter SimpleCov::Formatter::MultiFormatter.new(
          [SimpleCov::Formatter::HTMLFormatter,
           SimpleCov::Formatter::Codecov]
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

Rake::ExtensionTask.new("ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
  ext.ext_dir = 'ext/ddtrace_profiling_native_extension'
end

Rake::ExtensionTask.new("ddtrace_profiling_loader.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
  ext.ext_dir = 'ext/ddtrace_profiling_loader'
end

desc 'Runs the sorbet type checker on the codebase'
task :typecheck do
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
    $stderr.puts 'Sorry, cannot run sorbet type checker on older rubies :(' # rubocop:disable Style/StderrPuts
  else
    begin
      sh 'srb tc'
    rescue
      $stderr.puts( # rubocop:disable Style/StderrPuts
        %(
+------------------------------------------------------------------------------+
|  **Hello there, fellow contributor who just triggered a Sorbet type error**  |
|                                                                              |
| We're still experimenting with Sorbet on this codebase. If possible, take a  |
| stab at getting it to work, but feel free to unblock yourself by adding      |
| a `# typed: false` or `# typed: ignore` comment at the top of files which    |
| Sorbet is struggling with.                                                   |
|                                                                              |
| In particular, if you're adding a new integration, you'll need to use this   |
| mechanism as Sorbet does not play well with optional dependencies.           |
+------------------------------------------------------------------------------+
)
      )
      raise
    end
  end
end

desc 'Runs rubocop + type check + main test suite'
task default: ['rubocop', 'typecheck', 'spec:main']

desc 'Runs the default task in parallel'
multitask fastdefault: ['rubocop', 'typecheck', 'spec:main']
