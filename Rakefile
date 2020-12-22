require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
require 'rspec/core/rake_task'
require 'rake/testtask'
require 'appraisal'
require 'yard'

Dir.glob('tasks/*.rake').each { |r| import r }

desc 'Run RSpec'
# rubocop:disable Metrics/BlockLength
namespace :spec do
  task all: [:main, :benchmark,
             :rails, :railsredis, :railsactivejob,
             :elasticsearch, :http, :redis, :sidekiq, :sinatra]

  RSpec::Core::RakeTask.new(:main) do |t, args|
    t.pattern = 'spec/**/*_spec.rb'
    t.exclude_pattern = 'spec/**/{contrib,benchmark,redis,opentracer,opentelemetry}/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:benchmark) do |t, args|
    t.pattern = 'spec/ddtrace/benchmark/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:opentracer) do |t, args|
    t.pattern = 'spec/ddtrace/opentracer/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:opentelemetry) do |t, args|
    t.pattern = 'spec/ddtrace/opentelemetry/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:rails) do |t, args|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*_spec.rb'
    t.exclude_pattern = 'spec/ddtrace/contrib/rails/**/*{active_job,disable_env,redis_cache}*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsredis) do |t, args|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsactivejob) do |t, args|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*active_job*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsdisableenv) do |t, args|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*disable_env*_spec.rb'
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

  [
    :action_cable,
    :action_pack,
    :action_view,
    :active_model_serializers,
    :active_record,
    :active_support,
    :aws,
    :concurrent_ruby,
    :cucumber,
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
    :httprb,
    :kafka,
    :mongodb,
    :mysql2,
    :presto,
    :qless,
    :que,
    :racecar,
    :rack,
    :rake,
    :redis,
    :resque,
    :rest_client,
    :rspec,
    :sequel,
    :shoryuken,
    :sidekiq,
    :sinatra,
    :sneakers,
    :sucker_punch,
    :suite
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/ddtrace/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end
end

namespace :test do
  task all: [:main,
             :rails,
             :monkey]

  Rake::TestTask.new(:main) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/**/*_test.rb'].reject do |path|
      path.include?('contrib') ||
        path.include?('benchmark') ||
        path.include?('redis') ||
        path.include?('monkey_test.rb')
    end
  end

  Rake::TestTask.new(:rails) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/contrib/rails/**/*_test.rb']
  end

  [
  ].each do |contrib|
    Rake::TestTask.new(contrib) do |t|
      t.libs << %w[test lib]
      t.test_files = FileList["test/contrib/#{contrib}/*_test.rb"]
    end
  end

  Rake::TestTask.new(:monkey) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/monkey_test.rb']
  end
end

Rake::TestTask.new(:benchmark) do |t|
  t.libs << %w[test lib]
  t.test_files = FileList['test/benchmark_test.rb']
end

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
  RuboCop::RakeTask.new(:rubocop) do |t|
    t.options << ['-D', '--force-exclusion']
    t.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'spec/**/*.rb', 'Gemfile', 'Rakefile']
  end
end

YARD::Rake::YardocTask.new(:docs) do |t|
  t.options += ['--title', "ddtrace #{Datadog::VERSION::STRING} documentation"]
  t.options += ['--markup', 'markdown']
  t.options += ['--markup-provider', 'redcarpet']
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
def declare(*args)
  total_executors = ENV.key?('CIRCLE_NODE_TOTAL') ? ENV['CIRCLE_NODE_TOTAL'].to_i : nil
  current_executor = ENV.key?('CIRCLE_NODE_INDEX') ? ENV['CIRCLE_NODE_INDEX'].to_i : nil

  if total_executors && current_executor && total_executors > 1
    @execution_count ||= 0
    @execution_count += 1
    sh(*args) if @execution_count % total_executors == current_executor
  else
    sh(*args)
  end
end

desc 'CI task; it runs all tests for current version of Ruby'
task :ci do
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(Datadog::VERSION::MINIMUM_RUBY_VERSION)
    raise NotImplementedError, "Ruby versions < #{Datadog::VERSION::MINIMUM_RUBY_VERSION} are not supported!"
  elsif Gem::Version.new('2.0.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      declare 'bundle exec appraisal contrib-old rake test:monkey'
      # Contrib specs
      declare 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib-old rake spec:active_record'
      declare 'bundle exec appraisal contrib-old rake spec:active_support'
      declare 'bundle exec appraisal contrib-old rake spec:aws'
      declare 'bundle exec appraisal contrib-old rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib-old rake spec:dalli'
      declare 'bundle exec appraisal contrib-old rake spec:delayed_job'
      declare 'bundle exec appraisal contrib-old rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib-old rake spec:ethon'
      declare 'bundle exec appraisal contrib-old rake spec:excon'
      declare 'bundle exec appraisal contrib-old rake spec:faraday'
      declare 'bundle exec appraisal contrib-old rake spec:http'
      declare 'bundle exec appraisal contrib-old rake spec:httprb'
      declare 'bundle exec appraisal contrib-old rake spec:mongodb'
      declare 'bundle exec appraisal contrib-old rake spec:mysql2'
      declare 'bundle exec appraisal contrib-old rake spec:rack'
      declare 'bundle exec appraisal contrib-old rake spec:rake'
      declare 'bundle exec appraisal contrib-old rake spec:redis'
      declare 'bundle exec appraisal contrib-old rake spec:resque'
      declare 'bundle exec appraisal contrib-old rake spec:rest_client'
      declare 'bundle exec appraisal contrib-old rake spec:rspec'
      declare 'bundle exec appraisal contrib-old rake spec:sequel'
      declare 'bundle exec appraisal contrib-old rake spec:sidekiq'
      declare 'bundle exec appraisal contrib-old rake spec:sinatra'
      declare 'bundle exec appraisal contrib-old rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib-old rake spec:suite'
      # Rails minitests
      declare 'bundle exec appraisal rails30-postgres rake test:rails'
      declare 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails32-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails32-postgres rake test:rails'
      declare 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails30-postgres rake spec:rails'
      declare 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails32-postgres rake spec:rails'
      # Rails suite specs
      declare 'bundle exec appraisal rails32-postgres rake spec:action_pack'
      declare 'bundle exec appraisal rails32-postgres rake spec:action_view'
      declare 'bundle exec appraisal rails32-mysql2 rake spec:active_record'
      declare 'bundle exec appraisal rails32-postgres rake spec:active_support'
    end
  elsif Gem::Version.new('2.1.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      declare 'bundle exec appraisal contrib-old rake test:monkey'
      # Contrib specs
      declare 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib-old rake spec:active_record'
      declare 'bundle exec appraisal contrib-old rake spec:active_support'
      declare 'bundle exec appraisal contrib-old rake spec:aws'
      declare 'bundle exec appraisal contrib-old rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib-old rake spec:dalli'
      declare 'bundle exec appraisal contrib-old rake spec:delayed_job'
      declare 'bundle exec appraisal contrib-old rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib-old rake spec:ethon'
      declare 'bundle exec appraisal contrib-old rake spec:excon'
      declare 'bundle exec appraisal contrib-old rake spec:faraday'
      declare 'bundle exec appraisal contrib-old rake spec:http'
      declare 'bundle exec appraisal contrib-old rake spec:httprb'
      declare 'bundle exec appraisal contrib-old rake spec:kafka'
      declare 'bundle exec appraisal contrib-old rake spec:mongodb'
      declare 'bundle exec appraisal contrib-old rake spec:mysql2'
      declare 'bundle exec appraisal contrib-old rake spec:presto'
      declare 'bundle exec appraisal contrib-old rake spec:rack'
      declare 'bundle exec appraisal contrib-old rake spec:rake'
      declare 'bundle exec appraisal contrib-old rake spec:redis'
      declare 'bundle exec appraisal contrib-old rake spec:resque'
      declare 'bundle exec appraisal contrib-old rake spec:rest_client'
      declare 'bundle exec appraisal contrib-old rake spec:rspec'
      declare 'bundle exec appraisal contrib-old rake spec:sequel'
      declare 'bundle exec appraisal contrib-old rake spec:sidekiq'
      declare 'bundle exec appraisal contrib-old rake spec:sinatra'
      declare 'bundle exec appraisal contrib-old rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib-old rake spec:suite'
      # Rails minitests
      declare 'bundle exec appraisal rails30-postgres rake test:rails'
      declare 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails32-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails32-postgres rake test:rails'
      declare 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails4-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails4-postgres rake test:rails'
      declare 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails30-postgres rake spec:rails'
      declare 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails32-postgres rake spec:rails'
      declare 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails4-postgres rake spec:rails'
      # Rails suite specs
      declare 'bundle exec appraisal rails32-postgres rake spec:action_pack'
      declare 'bundle exec appraisal rails32-postgres rake spec:action_view'
      declare 'bundle exec appraisal rails32-mysql2 rake spec:active_record'
      declare 'bundle exec appraisal rails32-postgres rake spec:active_support'
    end
  elsif Gem::Version.new('2.2.0') <= Gem::Version.new(RUBY_VERSION)\
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      # Contrib specs
      declare 'bundle exec appraisal contrib rake spec:action_pack'
      declare 'bundle exec appraisal contrib rake spec:action_view'
      declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib rake spec:active_record'
      declare 'bundle exec appraisal contrib rake spec:active_support'
      declare 'bundle exec appraisal contrib rake spec:aws'
      declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib rake spec:dalli'
      declare 'bundle exec appraisal contrib rake spec:delayed_job'
      declare 'bundle exec appraisal contrib rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib rake spec:ethon'
      declare 'bundle exec appraisal contrib rake spec:excon'
      declare 'bundle exec appraisal contrib rake spec:faraday'
      declare 'bundle exec appraisal contrib rake spec:grape'
      declare 'bundle exec appraisal contrib rake spec:graphql'
      declare 'bundle exec appraisal contrib rake spec:grpc'
      declare 'bundle exec appraisal contrib rake spec:http'
      declare 'bundle exec appraisal contrib rake spec:httprb'
      declare 'bundle exec appraisal contrib rake spec:kafka'
      declare 'bundle exec appraisal contrib rake spec:mongodb'
      declare 'bundle exec appraisal contrib rake spec:mysql2'
      declare 'bundle exec appraisal contrib rake spec:presto'
      declare 'bundle exec appraisal contrib rake spec:qless'
      declare 'bundle exec appraisal contrib rake spec:que'
      declare 'bundle exec appraisal contrib rake spec:racecar'
      declare 'bundle exec appraisal contrib rake spec:rack'
      declare 'bundle exec appraisal contrib rake spec:rake'
      declare 'bundle exec appraisal contrib rake spec:redis'
      declare 'bundle exec appraisal contrib rake spec:resque'
      declare 'bundle exec appraisal contrib rake spec:rest_client'
      declare 'bundle exec appraisal contrib rake spec:rspec'
      declare 'bundle exec appraisal contrib rake spec:sequel'
      declare 'bundle exec appraisal contrib rake spec:shoryuken'
      declare 'bundle exec appraisal contrib rake spec:sidekiq'
      declare 'bundle exec appraisal contrib rake spec:sinatra'
      declare 'bundle exec appraisal contrib rake spec:sneakers'
      declare 'bundle exec appraisal contrib rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib rake spec:suite'
      # Rails minitests
      declare 'bundle exec appraisal rails30-postgres rake test:rails'
      declare 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails32-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails32-postgres rake test:rails'
      declare 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails4-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails4-postgres rake test:rails'
      declare 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails4-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails5-postgres rake test:rails'
      declare 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails30-postgres rake spec:rails'
      declare 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails32-postgres rake spec:rails'
      declare 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails4-postgres rake spec:rails'
      declare 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails5-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.3.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      # Contrib specs
      declare 'bundle exec appraisal contrib rake spec:action_pack'
      declare 'bundle exec appraisal contrib rake spec:action_view'
      declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib rake spec:active_record'
      declare 'bundle exec appraisal contrib rake spec:active_support'
      declare 'bundle exec appraisal contrib rake spec:aws'
      declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib rake spec:dalli'
      declare 'bundle exec appraisal contrib rake spec:delayed_job'
      declare 'bundle exec appraisal contrib rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib rake spec:ethon'
      declare 'bundle exec appraisal contrib rake spec:excon'
      declare 'bundle exec appraisal contrib rake spec:faraday'
      declare 'bundle exec appraisal contrib rake spec:grape'
      declare 'bundle exec appraisal contrib rake spec:graphql'
      declare 'bundle exec appraisal contrib rake spec:grpc'
      declare 'bundle exec appraisal contrib rake spec:http'
      declare 'bundle exec appraisal contrib rake spec:httprb'
      declare 'bundle exec appraisal contrib rake spec:kafka'
      declare 'bundle exec appraisal contrib rake spec:mongodb'
      declare 'bundle exec appraisal contrib rake spec:mysql2'
      declare 'bundle exec appraisal contrib rake spec:presto'
      declare 'bundle exec appraisal contrib rake spec:que'
      declare 'bundle exec appraisal contrib rake spec:racecar'
      declare 'bundle exec appraisal contrib rake spec:rack'
      declare 'bundle exec appraisal contrib rake spec:rake'
      declare 'bundle exec appraisal contrib rake spec:redis'
      declare 'bundle exec appraisal contrib rake spec:resque'
      declare 'bundle exec appraisal contrib rake spec:rest_client'
      declare 'bundle exec appraisal contrib rake spec:rspec'
      declare 'bundle exec appraisal contrib rake spec:sequel'
      declare 'bundle exec appraisal contrib rake spec:shoryuken'
      declare 'bundle exec appraisal contrib rake spec:sidekiq'
      declare 'bundle exec appraisal contrib rake spec:sinatra'
      declare 'bundle exec appraisal contrib rake spec:sneakers'
      declare 'bundle exec appraisal contrib rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      declare 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      declare 'bundle exec appraisal rails30-postgres rake test:rails'
      declare 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails32-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails32-postgres rake test:rails'
      declare 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails4-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails4-postgres rake test:rails'
      declare 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails4-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails5-postgres rake test:rails'
      declare 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails30-postgres rake spec:rails'
      declare 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails32-postgres rake spec:rails'
      declare 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails4-postgres rake spec:rails'
      declare 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails5-postgres rake spec:rails'

      # explicitly test resque-2x compatability
      declare 'bundle exec appraisal resque2-redis3 rake spec:resque'
      declare 'bundle exec appraisal resque2-redis4 rake spec:resque'
    end
  elsif Gem::Version.new('2.4.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'
    declare 'bundle exec rake spec:opentelemetry'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      # Contrib specs
      declare 'bundle exec appraisal contrib rake spec:action_pack'
      declare 'bundle exec appraisal contrib rake spec:action_view'
      declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib rake spec:active_record'
      declare 'bundle exec appraisal contrib rake spec:active_support'
      declare 'bundle exec appraisal contrib rake spec:aws'
      declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib rake spec:dalli'
      declare 'bundle exec appraisal contrib rake spec:delayed_job'
      declare 'bundle exec appraisal contrib rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib rake spec:ethon'
      declare 'bundle exec appraisal contrib rake spec:excon'
      declare 'bundle exec appraisal contrib rake spec:faraday'
      declare 'bundle exec appraisal contrib rake spec:grape'
      declare 'bundle exec appraisal contrib rake spec:graphql'
      declare 'bundle exec appraisal contrib rake spec:grpc'
      declare 'bundle exec appraisal contrib rake spec:http'
      declare 'bundle exec appraisal contrib rake spec:httprb'
      declare 'bundle exec appraisal contrib rake spec:kafka'
      declare 'bundle exec appraisal contrib rake spec:mongodb'
      declare 'bundle exec appraisal contrib rake spec:mysql2'
      declare 'bundle exec appraisal contrib rake spec:presto'
      declare 'bundle exec appraisal contrib rake spec:que'
      declare 'bundle exec appraisal contrib rake spec:racecar'
      declare 'bundle exec appraisal contrib rake spec:rack'
      declare 'bundle exec appraisal contrib rake spec:rake'
      declare 'bundle exec appraisal contrib rake spec:redis'
      declare 'bundle exec appraisal contrib rake spec:resque'
      declare 'bundle exec appraisal contrib rake spec:rest_client'
      declare 'bundle exec appraisal contrib rake spec:rspec'
      declare 'bundle exec appraisal contrib rake spec:sequel'
      declare 'bundle exec appraisal contrib rake spec:shoryuken'
      declare 'bundle exec appraisal contrib rake spec:sidekiq'
      declare 'bundle exec appraisal contrib rake spec:sinatra'
      declare 'bundle exec appraisal contrib rake spec:sneakers'
      declare 'bundle exec appraisal contrib rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      declare 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      declare 'bundle exec appraisal rails5-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails5-postgres rake test:rails'
      declare 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails5-postgres rake spec:rails'

      # explicitly test resque-2x compatability
      declare 'bundle exec appraisal resque2-redis3 rake spec:resque'
      declare 'bundle exec appraisal resque2-redis4 rake spec:resque'

      # explicitly test cucumber compatibility
      declare 'bundle exec appraisal cucumber3 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber4 rake spec:cucumber'
    end
  elsif Gem::Version.new('2.5.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.6.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'
    declare 'bundle exec rake spec:opentelemetry'
    # Contrib minitests
    # Contrib specs
    declare 'bundle exec appraisal contrib rake spec:action_pack'
    declare 'bundle exec appraisal contrib rake spec:action_view'
    declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
    declare 'bundle exec appraisal contrib rake spec:active_record'
    declare 'bundle exec appraisal contrib rake spec:active_support'
    declare 'bundle exec appraisal contrib rake spec:aws'
    declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
    declare 'bundle exec appraisal contrib rake spec:cucumber'
    declare 'bundle exec appraisal contrib rake spec:dalli'
    declare 'bundle exec appraisal contrib rake spec:delayed_job'
    declare 'bundle exec appraisal contrib rake spec:elasticsearch'
    declare 'bundle exec appraisal contrib rake spec:ethon'
    declare 'bundle exec appraisal contrib rake spec:excon'
    declare 'bundle exec appraisal contrib rake spec:faraday'
    declare 'bundle exec appraisal contrib rake spec:grape'
    declare 'bundle exec appraisal contrib rake spec:graphql'
    declare 'bundle exec appraisal contrib rake spec:grpc' if RUBY_PLATFORM != 'java' # protobuf not supported
    declare 'bundle exec appraisal contrib rake spec:http'
    declare 'bundle exec appraisal contrib rake spec:httprb'
    declare 'bundle exec appraisal contrib rake spec:kafka'
    declare 'bundle exec appraisal contrib rake spec:mongodb'
    declare 'bundle exec appraisal contrib rake spec:mysql2' if RUBY_PLATFORM != 'java' # built-in jdbc is used instead
    declare 'bundle exec appraisal contrib rake spec:presto'
    declare 'bundle exec appraisal contrib rake spec:qless'
    declare 'bundle exec appraisal contrib rake spec:que'
    declare 'bundle exec appraisal contrib rake spec:racecar'
    declare 'bundle exec appraisal contrib rake spec:rack'
    declare 'bundle exec appraisal contrib rake spec:rake'
    declare 'bundle exec appraisal contrib rake spec:redis'
    declare 'bundle exec appraisal contrib rake spec:resque'
    declare 'bundle exec appraisal contrib rake spec:rest_client'
    declare 'bundle exec appraisal contrib rake spec:rspec'
    declare 'bundle exec appraisal contrib rake spec:sequel'
    declare 'bundle exec appraisal contrib rake spec:shoryuken'
    declare 'bundle exec appraisal contrib rake spec:sidekiq'
    declare 'bundle exec appraisal contrib rake spec:sinatra'
    declare 'bundle exec appraisal contrib rake spec:sneakers'
    declare 'bundle exec appraisal contrib rake spec:sucker_punch'
    declare 'bundle exec appraisal contrib rake spec:suite'
    # Contrib specs with old gem versions
    declare 'bundle exec appraisal contrib-old rake spec:faraday'
    # Rails minitests
    # We only test Rails 5+ because older versions require Bundler < 2.0
    declare 'bundle exec appraisal rails5-mysql2 rake test:rails'
    declare 'bundle exec appraisal rails5-postgres rake test:rails'
    declare 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
    declare 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
    declare 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
    declare 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
    declare 'bundle exec appraisal rails6-mysql2 rake test:rails'
    declare 'bundle exec appraisal rails6-postgres rake test:rails'
    declare 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
    declare 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis'
    declare 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
    declare 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
    # Rails specs
    declare 'bundle exec appraisal rails5-mysql2 rake spec:action_cable'
    declare 'bundle exec appraisal rails5-mysql2 rake spec:rails'
    declare 'bundle exec appraisal rails5-postgres rake spec:rails'
    declare 'bundle exec appraisal rails6-mysql2 rake spec:action_cable'
    declare 'bundle exec appraisal rails6-mysql2 rake spec:rails'
    declare 'bundle exec appraisal rails6-postgres rake spec:rails'
    declare 'bundle exec appraisal rails61-mysql2 rake spec:action_cable'
    declare 'bundle exec appraisal rails61-mysql2 rake spec:rails'
    declare 'bundle exec appraisal rails61-mysql2 rake test:rails'
    declare 'bundle exec appraisal rails61-postgres rake spec:rails'
    declare 'bundle exec appraisal rails61-postgres rake spec:railsdisableenv'
    declare 'bundle exec appraisal rails61-postgres rake test:rails'
    declare 'bundle exec appraisal rails61-postgres-redis rake spec:railsredis'
    declare 'bundle exec appraisal rails61-postgres-sidekiq rake spec:railsactivejob'

    # explicitly test resque-2x compatability
    declare 'bundle exec appraisal resque2-redis3 rake spec:resque'
    declare 'bundle exec appraisal resque2-redis4 rake spec:resque'

    # explicitly test cucumber compatibility
    declare 'bundle exec appraisal cucumber3 rake spec:cucumber'
    declare 'bundle exec appraisal cucumber4 rake spec:cucumber'
    declare 'bundle exec appraisal cucumber5 rake spec:cucumber'
  elsif Gem::Version.new('2.6.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'
    declare 'bundle exec rake spec:opentelemetry'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      # Contrib specs
      declare 'bundle exec appraisal contrib rake spec:action_pack'
      declare 'bundle exec appraisal contrib rake spec:action_view'
      declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib rake spec:active_record'
      declare 'bundle exec appraisal contrib rake spec:active_support'
      declare 'bundle exec appraisal contrib rake spec:aws'
      declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib rake spec:cucumber'
      declare 'bundle exec appraisal contrib rake spec:dalli'
      declare 'bundle exec appraisal contrib rake spec:delayed_job'
      declare 'bundle exec appraisal contrib rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib rake spec:ethon'
      declare 'bundle exec appraisal contrib rake spec:excon'
      declare 'bundle exec appraisal contrib rake spec:faraday'
      declare 'bundle exec appraisal contrib rake spec:grape'
      declare 'bundle exec appraisal contrib rake spec:graphql'
      declare 'bundle exec appraisal contrib rake spec:grpc'
      declare 'bundle exec appraisal contrib rake spec:http'
      declare 'bundle exec appraisal contrib rake spec:httprb'
      declare 'bundle exec appraisal contrib rake spec:kafka'
      declare 'bundle exec appraisal contrib rake spec:mongodb'
      declare 'bundle exec appraisal contrib rake spec:mysql2'
      declare 'bundle exec appraisal contrib rake spec:presto'
      declare 'bundle exec appraisal contrib rake spec:qless'
      declare 'bundle exec appraisal contrib rake spec:que'
      declare 'bundle exec appraisal contrib rake spec:racecar'
      declare 'bundle exec appraisal contrib rake spec:rack'
      declare 'bundle exec appraisal contrib rake spec:rake'
      declare 'bundle exec appraisal contrib rake spec:redis'
      declare 'bundle exec appraisal contrib rake spec:resque'
      declare 'bundle exec appraisal contrib rake spec:rest_client'
      declare 'bundle exec appraisal contrib rake spec:rspec'
      declare 'bundle exec appraisal contrib rake spec:sequel'
      declare 'bundle exec appraisal contrib rake spec:shoryuken'
      declare 'bundle exec appraisal contrib rake spec:sidekiq'
      declare 'bundle exec appraisal contrib rake spec:sinatra'
      declare 'bundle exec appraisal contrib rake spec:sneakers'
      declare 'bundle exec appraisal contrib rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib rake spec:suite'

      # Contrib specs with old gem versions
      declare 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      declare 'bundle exec appraisal rails5-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails5-postgres rake test:rails'
      declare 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails6-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails6-postgres rake test:rails'
      declare 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails5-mysql2 rake spec:action_cable'
      declare 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails5-postgres rake spec:rails'
      declare 'bundle exec appraisal rails6-mysql2 rake spec:action_cable'
      declare 'bundle exec appraisal rails6-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails6-postgres rake spec:rails'
      declare 'bundle exec appraisal rails61-mysql2 rake spec:action_cable'
      declare 'bundle exec appraisal rails61-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails61-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails61-postgres rake spec:rails'
      declare 'bundle exec appraisal rails61-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails61-postgres rake test:rails'
      declare 'bundle exec appraisal rails61-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails61-postgres-sidekiq rake spec:railsactivejob'

      # explicitly test resque-2x compatability
      declare 'bundle exec appraisal resque2-redis3 rake spec:resque'
      declare 'bundle exec appraisal resque2-redis4 rake spec:resque'

      # explicitly test cucumber compatibility
      declare 'bundle exec appraisal cucumber3 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber4 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber5 rake spec:cucumber'
    end
  elsif Gem::Version.new('2.7.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0.0')
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'
    declare 'bundle exec rake spec:opentelemetry'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      # Contrib specs
      declare 'bundle exec appraisal contrib rake spec:action_pack'
      declare 'bundle exec appraisal contrib rake spec:action_view'
      declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib rake spec:active_record'
      declare 'bundle exec appraisal contrib rake spec:active_support'
      declare 'bundle exec appraisal contrib rake spec:aws'
      declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib rake spec:cucumber'
      declare 'bundle exec appraisal contrib rake spec:dalli'
      declare 'bundle exec appraisal contrib rake spec:delayed_job'
      declare 'bundle exec appraisal contrib rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib rake spec:ethon'
      declare 'bundle exec appraisal contrib rake spec:excon'
      declare 'bundle exec appraisal contrib rake spec:faraday'
      declare 'bundle exec appraisal contrib rake spec:grape'
      declare 'bundle exec appraisal contrib rake spec:graphql'
      declare 'bundle exec appraisal contrib rake spec:grpc'
      declare 'bundle exec appraisal contrib rake spec:http'
      declare 'bundle exec appraisal contrib rake spec:httprb'
      declare 'bundle exec appraisal contrib rake spec:kafka'
      declare 'bundle exec appraisal contrib rake spec:mongodb'
      declare 'bundle exec appraisal contrib rake spec:mysql2'
      declare 'bundle exec appraisal contrib rake spec:presto'
      declare 'bundle exec appraisal contrib rake spec:qless'
      declare 'bundle exec appraisal contrib rake spec:que'
      declare 'bundle exec appraisal contrib rake spec:racecar'
      declare 'bundle exec appraisal contrib rake spec:rack'
      declare 'bundle exec appraisal contrib rake spec:rake'
      declare 'bundle exec appraisal contrib rake spec:redis'
      declare 'bundle exec appraisal contrib rake spec:resque'
      declare 'bundle exec appraisal contrib rake spec:rest_client'
      declare 'bundle exec appraisal contrib rake spec:rspec'
      declare 'bundle exec appraisal contrib rake spec:sequel'
      declare 'bundle exec appraisal contrib rake spec:shoryuken'
      declare 'bundle exec appraisal contrib rake spec:sidekiq'
      declare 'bundle exec appraisal contrib rake spec:sinatra'
      declare 'bundle exec appraisal contrib rake spec:sneakers'
      declare 'bundle exec appraisal contrib rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib rake spec:suite'

      # Contrib specs with old gem versions
      declare 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      declare 'bundle exec appraisal rails5-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails5-postgres rake test:rails'
      declare 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails6-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails6-postgres rake test:rails'
      declare 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis'
      declare 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
      declare 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
      # Rails specs
      declare 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails5-postgres rake spec:rails'
      declare 'bundle exec appraisal rails6-mysql2 rake spec:action_cable'
      declare 'bundle exec appraisal rails6-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails6-postgres rake spec:rails'
      declare 'bundle exec appraisal rails61-mysql2 rake spec:action_cable'
      declare 'bundle exec appraisal rails61-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails61-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails61-postgres rake spec:rails'
      declare 'bundle exec appraisal rails61-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails61-postgres rake test:rails'
      declare 'bundle exec appraisal rails61-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails61-postgres-sidekiq rake spec:railsactivejob'

      # explicitly test resque-2x compatability
      declare 'bundle exec appraisal resque2-redis3 rake spec:resque'
      declare 'bundle exec appraisal resque2-redis4 rake spec:resque'

      # explicitly test cucumber compatibility
      declare 'bundle exec appraisal cucumber3 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber4 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber5 rake spec:cucumber'
    end
  elsif Gem::Version.new('3.0.0') <= Gem::Version.new(RUBY_VERSION)
    # Main library
    declare 'bundle exec rake test:main'
    declare 'bundle exec rake spec:main'
    declare 'bundle exec rake spec:contrib'
    declare 'bundle exec rake spec:opentracer'
    declare 'bundle exec rake spec:opentelemetry'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      # Contrib specs
      declare 'bundle exec appraisal contrib rake spec:action_pack'
      declare 'bundle exec appraisal contrib rake spec:action_view'
      declare 'bundle exec appraisal contrib rake spec:active_model_serializers'
      declare 'bundle exec appraisal contrib rake spec:active_record'
      declare 'bundle exec appraisal contrib rake spec:active_support'
      declare 'bundle exec appraisal contrib rake spec:aws'
      declare 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      declare 'bundle exec appraisal contrib rake spec:cucumber'
      declare 'bundle exec appraisal contrib rake spec:dalli'
      declare 'bundle exec appraisal contrib rake spec:delayed_job'
      declare 'bundle exec appraisal contrib rake spec:elasticsearch'
      declare 'bundle exec appraisal contrib rake spec:ethon'
      declare 'bundle exec appraisal contrib rake spec:excon'
      declare 'bundle exec appraisal contrib rake spec:faraday'
      declare 'bundle exec appraisal contrib rake spec:grape'
      declare 'bundle exec appraisal contrib rake spec:graphql'
      # declare 'bundle exec appraisal contrib rake spec:grpc' # Pending https://github.com/protocolbuffers/protobuf/issues/7922
      declare 'bundle exec appraisal contrib rake spec:http'
      declare 'bundle exec appraisal contrib rake spec:httprb'
      declare 'bundle exec appraisal contrib rake spec:kafka'
      declare 'bundle exec appraisal contrib rake spec:mongodb'
      declare 'bundle exec appraisal contrib rake spec:mysql2'
      declare 'bundle exec appraisal contrib rake spec:presto'
      declare 'bundle exec appraisal contrib rake spec:qless'
      declare 'bundle exec appraisal contrib rake spec:que'
      # declare 'bundle exec appraisal contrib rake spec:racecar' # Pending release of our fix: https://github.com/appsignal/rdkafka-ruby/pull/144
      declare 'bundle exec appraisal contrib rake spec:rack'
      declare 'bundle exec appraisal contrib rake spec:rake'
      declare 'bundle exec appraisal contrib rake spec:redis'
      declare 'bundle exec appraisal contrib rake spec:resque'
      declare 'bundle exec appraisal contrib rake spec:rest_client'
      declare 'bundle exec appraisal contrib rake spec:rspec'
      declare 'bundle exec appraisal contrib rake spec:sequel'
      declare 'bundle exec appraisal contrib rake spec:shoryuken'
      declare 'bundle exec appraisal contrib rake spec:sidekiq'
      declare 'bundle exec appraisal contrib rake spec:sinatra'
      declare 'bundle exec appraisal contrib rake spec:sneakers'
      declare 'bundle exec appraisal contrib rake spec:sucker_punch'
      declare 'bundle exec appraisal contrib rake spec:suite'

      # Rails
      declare 'bundle exec appraisal rails61-mysql2 rake spec:action_cable'
      declare 'bundle exec appraisal rails61-mysql2 rake spec:rails'
      declare 'bundle exec appraisal rails61-mysql2 rake test:rails'
      declare 'bundle exec appraisal rails61-postgres rake spec:rails'
      declare 'bundle exec appraisal rails61-postgres rake spec:railsdisableenv'
      declare 'bundle exec appraisal rails61-postgres rake test:rails'
      declare 'bundle exec appraisal rails61-postgres-redis rake spec:railsredis'
      declare 'bundle exec appraisal rails61-postgres-sidekiq rake spec:railsactivejob'

      # explicitly test resque-2x compatability
      declare 'bundle exec appraisal resque2-redis3 rake spec:resque'
      declare 'bundle exec appraisal resque2-redis4 rake spec:resque'

      # explicitly test cucumber compatibility
      declare 'bundle exec appraisal cucumber3 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber4 rake spec:cucumber'
      declare 'bundle exec appraisal cucumber5 rake spec:cucumber'
    end
  end
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
        formatter SimpleCov::Formatter::MultiFormatter.new([SimpleCov::Formatter::HTMLFormatter,
                                                            SimpleCov::Formatter::Codecov])
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

task default: :test
