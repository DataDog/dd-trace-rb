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
    :mongodb,
    :mysql2,
    :presto,
    :racecar,
    :rack,
    :rake,
    :redis,
    :resque,
    :rest_client,
    :sequel,
    :shoryuken,
    :sidekiq,
    :sinatra,
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
             :sidekiq, :monkey]

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
    :grape,
    :sidekiq,
    :sucker_punch
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

desc 'CI task; it runs all tests for current version of Ruby'
task :ci do
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(Datadog::VERSION::MINIMUM_RUBY_VERSION)
    raise NotImplementedError, "Ruby versions < #{Datadog::VERSION::MINIMUM_RUBY_VERSION} are not supported!"
  elsif Gem::Version.new('2.0.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib-old rake test:monkey'
      sh 'bundle exec appraisal contrib-old rake test:sidekiq'
      sh 'bundle exec appraisal contrib-old rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib-old rake spec:active_record'
      sh 'bundle exec appraisal contrib-old rake spec:active_support'
      sh 'bundle exec appraisal contrib-old rake spec:aws'
      sh 'bundle exec appraisal contrib-old rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib-old rake spec:dalli'
      sh 'bundle exec appraisal contrib-old rake spec:delayed_job'
      sh 'bundle exec appraisal contrib-old rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib-old rake spec:ethon'
      sh 'bundle exec appraisal contrib-old rake spec:excon'
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      sh 'bundle exec appraisal contrib-old rake spec:http'
      sh 'bundle exec appraisal contrib-old rake spec:mongodb'
      sh 'bundle exec appraisal contrib-old rake spec:mysql2'
      sh 'bundle exec appraisal contrib-old rake spec:rack'
      sh 'bundle exec appraisal contrib-old rake spec:rake'
      sh 'bundle exec appraisal contrib-old rake spec:redis'
      sh 'bundle exec appraisal contrib-old rake spec:resque'
      sh 'bundle exec appraisal contrib-old rake spec:rest_client'
      sh 'bundle exec appraisal contrib-old rake spec:sequel'
      sh 'bundle exec appraisal contrib-old rake spec:sidekiq'
      sh 'bundle exec appraisal contrib-old rake spec:sinatra'
      sh 'bundle exec appraisal contrib-old rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib-old rake spec:suite'
      # Rails minitests
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
      # Rails suite specs
      sh 'bundle exec appraisal rails32-postgres rake spec:action_pack'
      sh 'bundle exec appraisal rails32-postgres rake spec:action_view'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:active_record'
      sh 'bundle exec appraisal rails32-postgres rake spec:active_support'
    end
  elsif Gem::Version.new('2.1.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib-old rake test:monkey'
      sh 'bundle exec appraisal contrib-old rake test:sidekiq'
      sh 'bundle exec appraisal contrib-old rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib-old rake spec:active_record'
      sh 'bundle exec appraisal contrib-old rake spec:active_support'
      sh 'bundle exec appraisal contrib-old rake spec:aws'
      sh 'bundle exec appraisal contrib-old rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib-old rake spec:dalli'
      sh 'bundle exec appraisal contrib-old rake spec:delayed_job'
      sh 'bundle exec appraisal contrib-old rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib-old rake spec:ethon'
      sh 'bundle exec appraisal contrib-old rake spec:excon'
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      sh 'bundle exec appraisal contrib-old rake spec:http'
      sh 'bundle exec appraisal contrib-old rake spec:mongodb'
      sh 'bundle exec appraisal contrib-old rake spec:mysql2'
      sh 'bundle exec appraisal contrib-old rake spec:presto'
      sh 'bundle exec appraisal contrib-old rake spec:rack'
      sh 'bundle exec appraisal contrib-old rake spec:rake'
      sh 'bundle exec appraisal contrib-old rake spec:redis'
      sh 'bundle exec appraisal contrib-old rake spec:resque'
      sh 'bundle exec appraisal contrib-old rake spec:rest_client'
      sh 'bundle exec appraisal contrib-old rake spec:sequel'
      sh 'bundle exec appraisal contrib-old rake spec:sidekiq'
      sh 'bundle exec appraisal contrib-old rake spec:sinatra'
      sh 'bundle exec appraisal contrib-old rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib-old rake spec:suite'
      # Rails minitests
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails4-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails4-postgres rake test:rails'
      sh 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
      sh 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails4-postgres rake spec:rails'
      # Rails suite specs
      sh 'bundle exec appraisal rails32-postgres rake spec:action_pack'
      sh 'bundle exec appraisal rails32-postgres rake spec:action_view'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:active_record'
      sh 'bundle exec appraisal rails32-postgres rake spec:active_support'
    end
  elsif Gem::Version.new('2.2.0') <= Gem::Version.new(RUBY_VERSION)\
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:action_pack'
      sh 'bundle exec appraisal contrib rake spec:action_view'
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:aws'
      sh 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:delayed_job'
      sh 'bundle exec appraisal contrib rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib rake spec:ethon'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:grape'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:mysql2'
      sh 'bundle exec appraisal contrib rake spec:presto'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rack'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:rest_client'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      sh 'bundle exec appraisal contrib rake spec:shoryuken'
      sh 'bundle exec appraisal contrib rake spec:sidekiq'
      sh 'bundle exec appraisal contrib rake spec:sinatra'
      sh 'bundle exec appraisal contrib rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib rake spec:suite'
      # Rails minitests
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails4-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails4-postgres rake test:rails'
      sh 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails4-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
      sh 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails4-postgres rake spec:rails'
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.3.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:action_pack'
      sh 'bundle exec appraisal contrib rake spec:action_view'
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:aws'
      sh 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:delayed_job'
      sh 'bundle exec appraisal contrib rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib rake spec:ethon'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:grape'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:mysql2'
      sh 'bundle exec appraisal contrib rake spec:presto'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rack'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:rest_client'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      sh 'bundle exec appraisal contrib rake spec:shoryuken'
      sh 'bundle exec appraisal contrib rake spec:sidekiq'
      sh 'bundle exec appraisal contrib rake spec:sinatra'
      sh 'bundle exec appraisal contrib rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails4-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails4-postgres rake test:rails'
      sh 'bundle exec appraisal rails4-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails4-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails4-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
      sh 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails4-postgres rake spec:rails'
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.4.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    sh 'bundle exec rake spec:opentelemetry'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Benchmarks
      sh 'bundle exec rake benchmark'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:action_pack'
      sh 'bundle exec appraisal contrib rake spec:action_view'
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:aws'
      sh 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:delayed_job'
      sh 'bundle exec appraisal contrib rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib rake spec:ethon'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:grape'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:mysql2'
      sh 'bundle exec appraisal contrib rake spec:presto'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rack'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:rest_client'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      sh 'bundle exec appraisal contrib rake spec:shoryuken'
      sh 'bundle exec appraisal contrib rake spec:sidekiq'
      sh 'bundle exec appraisal contrib rake spec:sinatra'
      sh 'bundle exec appraisal contrib rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.5.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.6.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    sh 'bundle exec rake spec:opentelemetry'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Benchmarks
      sh 'bundle exec rake benchmark'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:action_pack'
      sh 'bundle exec appraisal contrib rake spec:action_view'
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:aws'
      sh 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:delayed_job'
      sh 'bundle exec appraisal contrib rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib rake spec:ethon'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:grape'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:mysql2'
      sh 'bundle exec appraisal contrib rake spec:presto'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rack'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:rest_client'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      sh 'bundle exec appraisal contrib rake spec:shoryuken'
      sh 'bundle exec appraisal contrib rake spec:sidekiq'
      sh 'bundle exec appraisal contrib rake spec:sinatra'
      sh 'bundle exec appraisal contrib rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails6-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails6-postgres rake test:rails'
      sh 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails5-mysql2 rake spec:action_cable'
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
      # sh 'bundle exec appraisal rails6-mysql2 rake spec:action_cable' # TODO: Hangs CI jobs... fix and re-enable.
      sh 'bundle exec appraisal rails6-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails6-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.6.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    sh 'bundle exec rake spec:opentelemetry'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Benchmarks
      sh 'bundle exec rake benchmark'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:action_pack'
      sh 'bundle exec appraisal contrib rake spec:action_view'
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:aws'
      sh 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:delayed_job'
      sh 'bundle exec appraisal contrib rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib rake spec:ethon'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:grape'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:mysql2'
      sh 'bundle exec appraisal contrib rake spec:presto'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rack'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:rest_client'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      sh 'bundle exec appraisal contrib rake spec:shoryuken'
      sh 'bundle exec appraisal contrib rake spec:sidekiq'
      sh 'bundle exec appraisal contrib rake spec:sinatra'
      sh 'bundle exec appraisal contrib rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails6-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails6-postgres rake test:rails'
      sh 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails5-mysql2 rake spec:action_cable'
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
      # sh 'bundle exec appraisal rails6-mysql2 rake spec:action_cable' # TODO: Hangs CI jobs... fix and re-enable.
      sh 'bundle exec appraisal rails6-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails6-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.7.0') <= Gem::Version.new(RUBY_VERSION)
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'
    sh 'bundle exec rake spec:contrib'
    sh 'bundle exec rake spec:opentracer'
    sh 'bundle exec rake spec:opentelemetry'
    # Benchmarks
    sh 'bundle exec rake spec:benchmark'

    if RUBY_PLATFORM != 'java'
      # Benchmarks
      sh 'bundle exec rake benchmark'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:action_pack'
      sh 'bundle exec appraisal contrib rake spec:action_view'
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:aws'
      sh 'bundle exec appraisal contrib rake spec:concurrent_ruby'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:delayed_job'
      sh 'bundle exec appraisal contrib rake spec:elasticsearch'
      sh 'bundle exec appraisal contrib rake spec:ethon'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:grape'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:mysql2'
      sh 'bundle exec appraisal contrib rake spec:presto'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rack'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:rest_client'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      sh 'bundle exec appraisal contrib rake spec:shoryuken'
      sh 'bundle exec appraisal contrib rake spec:sidekiq'
      sh 'bundle exec appraisal contrib rake spec:sinatra'
      sh 'bundle exec appraisal contrib rake spec:sucker_punch'
      sh 'bundle exec appraisal contrib rake spec:suite'
      # Contrib specs with old gem versions
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      # Rails minitests
      # We only test Rails 5+ because older versions require Bundler < 2.0
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake spec:railsdisableenv'
      sh 'bundle exec appraisal rails6-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails6-postgres rake test:rails'
      sh 'bundle exec appraisal rails6-postgres-redis rake spec:railsredis'
      sh 'bundle exec appraisal rails6-postgres-redis-activesupport rake spec:railsredis'
      sh 'bundle exec appraisal rails6-postgres-sidekiq rake spec:railsactivejob'
      sh 'bundle exec appraisal rails6-postgres rake spec:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
      sh 'bundle exec appraisal rails6-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails6-postgres rake spec:rails'
    end
  end
end

task default: :test
