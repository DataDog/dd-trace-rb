require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
require 'rspec/core/rake_task'
require 'rake/testtask'
require 'appraisal'
require 'yard'

desc 'Run RSpec'
# rubocop:disable Metrics/BlockLength
namespace :spec do
  task all: [:main,
             :rails, :railsredis, :railssidekiq, :railsactivejob,
             :elasticsearch, :http, :redis, :sidekiq, :sinatra]

  RSpec::Core::RakeTask.new(:main) do |t|
    t.pattern = 'spec/**/*_spec.rb'
    t.exclude_pattern = 'spec/**/{contrib,benchmark,redis}/**/*_spec.rb'
  end

  RSpec::Core::RakeTask.new(:rails) do |t|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*_spec.rb'
    t.exclude_pattern = 'spec/ddtrace/contrib/rails/**/*{sidekiq,active_job,disable_env}*_spec.rb'
  end

  RSpec::Core::RakeTask.new(:railsredis) do |t|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*redis*_spec.rb'
  end

  RSpec::Core::RakeTask.new(:railssidekiq) do |t|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*sidekiq*_spec.rb'
  end

  RSpec::Core::RakeTask.new(:railsactivejob) do |t|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*active_job*_spec.rb'
  end

  RSpec::Core::RakeTask.new(:railsdisableenv) do |t|
    t.pattern = 'spec/ddtrace/contrib/rails/**/*disable_env*_spec.rb'
  end

  [
    :active_model_serializers,
    :active_record,
    :active_support,
    :aws,
    :dalli,
    :elasticsearch,
    :excon,
    :faraday,
    :grape,
    :graphql,
    :grpc,
    :http,
    :mongodb,
    :racecar,
    :rack,
    :rake,
    :redis,
    :resque,
    :sequel,
    :sidekiq,
    :sinatra,
    :sucker_punch
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t|
      t.pattern = "spec/ddtrace/contrib/#{contrib}/**/*_spec.rb"
    end
  end
end

namespace :test do
  task all: [:main,
             :rails, :railsredis, :railssidekiq, :railsactivejob,
             :elasticsearch, :http, :sidekiq, :sinatra, :monkey]

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
    t.test_files = FileList['test/contrib/rails/**/*_test.rb'].reject do |path|
      path.include?('redis') ||
        path.include?('sidekiq') ||
        path.include?('active_job') ||
        path.include?('disable_env')
    end
  end

  Rake::TestTask.new(:railsredis) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/contrib/rails/**/*redis*_test.rb']
  end

  Rake::TestTask.new(:railssidekiq) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/contrib/rails/**/*sidekiq*_test.rb']
  end

  Rake::TestTask.new(:railsactivejob) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/contrib/rails/**/*active_job*_test.rb']
  end

  Rake::TestTask.new(:railsdisableenv) do |t|
    t.libs << %w[test lib]
    t.test_files = FileList['test/contrib/rails/**/*disable_env*_test.rb']
  end

  [
    :aws,
    :elasticsearch,
    :grape,
    :http,
    :rack,
    :sidekiq,
    :sinatra,
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

desc 'create a new indexed repository'
task :'release:gem' do
  raise 'Missing environment variable S3_DIR' if !S3_DIR || S3_DIR.empty?
  # load existing deployed gems
  sh "aws s3 cp --exclude 'docs/*' --recursive s3://#{S3_BUCKET}/#{S3_DIR}/ ./rubygems/"

  # create folders
  sh 'mkdir -p ./gems'
  sh 'mkdir -p ./rubygems/gems/'
  sh 'mkdir -p ./rubygems/quick/'

  # copy previous builds
  sh 'cp ./rubygems/gems/* ./gems/'

  # build the gem
  Rake::Task['build'].execute

  # copy the output in the indexed folder
  sh 'cp pkg/*.gem ./gems/'

  # generate the gems index
  sh 'gem generate_index'

  # namespace everything under ./rubygems/
  sh 'cp -r ./gems/* ./rubygems/gems/'
  sh 'cp -r specs.* ./rubygems/'
  sh 'cp -r latest_specs.* ./rubygems/'
  sh 'cp -r prerelease_specs.* ./rubygems/'
  sh 'cp -r ./quick/* ./rubygems/quick/'

  # deploy a static gem registry
  sh "aws s3 cp --recursive ./rubygems/ s3://#{S3_BUCKET}/#{S3_DIR}/"
end

desc 'release the docs website'
task :'release:docs' => :docs do
  raise 'Missing environment variable S3_DIR' if !S3_DIR || S3_DIR.empty?
  sh "aws s3 cp --recursive doc/ s3://#{S3_BUCKET}/#{S3_DIR}/docs/"
end

desc 'CI task; it runs all tests for current version of Ruby'
task :ci do
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('1.9.3')
    raise NotImplementedError, 'Ruby versions < 1.9.3 are not supported!'
  elsif Gem::Version.new('1.9.3') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib-old rake test:aws'
      sh 'bundle exec appraisal contrib-old rake test:elasticsearch'
      sh 'bundle exec appraisal contrib-old rake test:http'
      sh 'bundle exec appraisal contrib-old rake test:monkey'
      sh 'bundle exec appraisal contrib-old rake test:rack'
      sh 'bundle exec appraisal contrib-old rake test:sinatra'
      sh 'bundle exec appraisal contrib-old rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib-old rake spec:active_record'
      sh 'bundle exec appraisal contrib-old rake spec:active_support'
      sh 'bundle exec appraisal contrib-old rake spec:dalli'
      sh 'bundle exec appraisal contrib-old rake spec:excon'
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      sh 'bundle exec appraisal contrib-old rake spec:http'
      sh 'bundle exec appraisal contrib-old rake spec:mongodb'
      sh 'bundle exec appraisal contrib-old rake spec:rake'
      sh 'bundle exec appraisal contrib-old rake spec:redis'
      sh 'bundle exec appraisal contrib-old rake spec:resque'
      sh 'bundle exec appraisal contrib-old rake spec:sequel'
      # Rails minitests
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake test:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.0.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib-old rake test:aws'
      sh 'bundle exec appraisal contrib-old rake test:elasticsearch'
      sh 'bundle exec appraisal contrib-old rake test:http'
      sh 'bundle exec appraisal contrib-old rake test:monkey'
      sh 'bundle exec appraisal contrib-old rake test:rack'
      sh 'bundle exec appraisal contrib-old rake test:sinatra'
      sh 'bundle exec appraisal contrib-old rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib-old rake spec:active_record'
      sh 'bundle exec appraisal contrib-old rake spec:active_support'
      sh 'bundle exec appraisal contrib-old rake spec:dalli'
      sh 'bundle exec appraisal contrib-old rake spec:excon'
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      sh 'bundle exec appraisal contrib-old rake spec:http'
      sh 'bundle exec appraisal contrib-old rake spec:mongodb'
      sh 'bundle exec appraisal contrib-old rake spec:rake'
      sh 'bundle exec appraisal contrib-old rake spec:redis'
      sh 'bundle exec appraisal contrib-old rake spec:resque'
      sh 'bundle exec appraisal contrib-old rake spec:sequel'
      # Rails minitests
      sh 'bundle exec appraisal contrib-old rake test:sidekiq'
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails30-postgres-sidekiq rake test:railssidekiq'
      sh 'bundle exec appraisal rails32-postgres-sidekiq rake test:railssidekiq'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.1.0') <= Gem::Version.new(RUBY_VERSION) \
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib-old rake test:aws'
      sh 'bundle exec appraisal contrib-old rake test:elasticsearch'
      sh 'bundle exec appraisal contrib-old rake test:http'
      sh 'bundle exec appraisal contrib-old rake test:monkey'
      sh 'bundle exec appraisal contrib-old rake test:rack'
      sh 'bundle exec appraisal contrib-old rake test:sinatra'
      sh 'bundle exec appraisal contrib-old rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib-old rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib-old rake spec:active_record'
      sh 'bundle exec appraisal contrib-old rake spec:active_support'
      sh 'bundle exec appraisal contrib-old rake spec:dalli'
      sh 'bundle exec appraisal contrib-old rake spec:excon'
      sh 'bundle exec appraisal contrib-old rake spec:faraday'
      sh 'bundle exec appraisal contrib-old rake spec:http'
      sh 'bundle exec appraisal contrib-old rake spec:mongodb'
      sh 'bundle exec appraisal contrib-old rake spec:rake'
      sh 'bundle exec appraisal contrib-old rake spec:redis'
      sh 'bundle exec appraisal contrib-old rake spec:resque'
      sh 'bundle exec appraisal contrib-old rake spec:sequel'
      # Rails minitests
      sh 'bundle exec appraisal contrib-old rake test:sidekiq'
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails4-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails4-postgres rake test:rails'
      sh 'bundle exec appraisal rails4-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails4-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails30-postgres-sidekiq rake test:railssidekiq'
      sh 'bundle exec appraisal rails32-postgres-sidekiq rake test:railssidekiq'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
      sh 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails4-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.2.0') <= Gem::Version.new(RUBY_VERSION)\
        && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:aws'
      sh 'bundle exec appraisal contrib rake test:elasticsearch'
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:http'
      sh 'bundle exec appraisal contrib rake test:rack'
      sh 'bundle exec appraisal contrib rake test:sinatra'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      # Rails minitests
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails4-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails4-postgres rake test:rails'
      sh 'bundle exec appraisal rails4-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails4-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails4-postgres-sidekiq rake test:railssidekiq'
      sh 'bundle exec appraisal rails4-postgres-sidekiq rake test:railsactivejob'
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake test:railssidekiq'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake test:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake test:railsdisableenv'
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

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:aws'
      sh 'bundle exec appraisal contrib rake test:elasticsearch'
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:http'
      sh 'bundle exec appraisal contrib rake test:rack'
      sh 'bundle exec appraisal contrib rake test:sinatra'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      # Rails minitests
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec appraisal rails30-postgres rake test:rails'
      sh 'bundle exec appraisal rails30-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails32-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails32-postgres rake test:rails'
      sh 'bundle exec appraisal rails32-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails32-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails4-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails4-postgres rake test:rails'
      sh 'bundle exec appraisal rails4-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails4-postgres rake test:railsdisableenv'
      sh 'bundle exec appraisal rails4-postgres-sidekiq rake test:railssidekiq'
      sh 'bundle exec appraisal rails4-postgres-sidekiq rake test:railsactivejob'
      sh 'bundle exec appraisal rails5-mysql2 rake test:rails'
      sh 'bundle exec appraisal rails5-postgres rake test:rails'
      sh 'bundle exec appraisal rails5-postgres-redis rake test:railsredis'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake test:railssidekiq'
      sh 'bundle exec appraisal rails5-postgres-sidekiq rake test:railsactivejob'
      sh 'bundle exec appraisal rails5-postgres rake test:railsdisableenv'
      # Rails specs
      sh 'bundle exec appraisal rails30-postgres rake spec:rails'
      sh 'bundle exec appraisal rails32-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails32-postgres rake spec:rails'
      sh 'bundle exec appraisal rails4-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails4-postgres rake spec:rails'
      sh 'bundle exec appraisal rails5-mysql2 rake spec:rails'
      sh 'bundle exec appraisal rails5-postgres rake spec:rails'
    end
  elsif Gem::Version.new('2.4.0') <= Gem::Version.new(RUBY_VERSION)
    # Main library
    sh 'bundle exec rake test:main'
    sh 'bundle exec rake spec:main'

    if RUBY_PLATFORM != 'java'
      # Contrib minitests
      sh 'bundle exec appraisal contrib rake test:aws'
      sh 'bundle exec appraisal contrib rake test:elasticsearch'
      sh 'bundle exec appraisal contrib rake test:grape'
      sh 'bundle exec appraisal contrib rake test:http'
      sh 'bundle exec appraisal contrib rake test:rack'
      sh 'bundle exec appraisal contrib rake test:sinatra'
      sh 'bundle exec appraisal contrib rake test:sucker_punch'
      # Contrib specs
      sh 'bundle exec appraisal contrib rake spec:active_model_serializers'
      sh 'bundle exec appraisal contrib rake spec:active_record'
      sh 'bundle exec appraisal contrib rake spec:active_support'
      sh 'bundle exec appraisal contrib rake spec:dalli'
      sh 'bundle exec appraisal contrib rake spec:excon'
      sh 'bundle exec appraisal contrib rake spec:faraday'
      sh 'bundle exec appraisal contrib rake spec:graphql'
      sh 'bundle exec appraisal contrib rake spec:grpc'
      sh 'bundle exec appraisal contrib rake spec:http'
      sh 'bundle exec appraisal contrib rake spec:mongodb'
      sh 'bundle exec appraisal contrib rake spec:racecar'
      sh 'bundle exec appraisal contrib rake spec:rake'
      sh 'bundle exec appraisal contrib rake spec:redis'
      sh 'bundle exec appraisal contrib rake spec:resque'
      sh 'bundle exec appraisal contrib rake spec:sequel'
      # Rails minitests
      sh 'bundle exec appraisal contrib rake test:sidekiq'
      sh 'bundle exec rake benchmark'
    end
  end
end

task default: :test
