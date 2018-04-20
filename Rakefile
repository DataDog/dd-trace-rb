require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task' if RUBY_VERSION >= '2.1.0'
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
    :active_record,
    :active_support,
    :aws,
    :dalli,
    :elasticsearch,
    :faraday,
    :grape,
    :graphql,
    :http,
    :mongodb,
    :racecar,
    :rack,
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
    :sequel,
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

if RUBY_VERSION >= '2.1.0'
  RuboCop::RakeTask.new(:rubocop) do |t|
    t.options << ['-D']
    t.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'Gemfile', 'Rakefile']
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

desc 'CI dependent task; it runs all parallel tests'
task :ci do
  # CircleCI uses this environment to store the node index (starting from 0)
  # check: https://circleci.com/docs/parallel-manual-setup/#env-splitting
  case ENV['CIRCLE_NODE_INDEX'].to_i
  when 0
    sh 'rvm $MRI_VERSIONS,$MRI_OLD_VERSIONS,$JRUBY_VERSIONS --verbose do rake test:main'
    # RSpec
    sh 'rvm $MRI_VERSIONS,$MRI_OLD_VERSIONS,$JRUBY_VERSIONS --verbose do rake spec:main'
  when 1
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:elasticsearch'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:http'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sequel'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sinatra'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:rack'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:grape'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:aws'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sucker_punch'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:monkey'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:elasticsearch'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:http'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:sinatra'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:sequel'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:rack'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:aws'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:sucker_punch'
    # RSpec
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:active_record'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:active_support'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:dalli'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:faraday'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:graphql'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:mongodb'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:racecar'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:redis'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake spec:resque'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:active_record'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:active_support'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:dalli'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:faraday'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:mongodb'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:redis'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake spec:resque'
  when 2
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sidekiq'
    sh 'rvm $SIDEKIQ_OLD_VERSIONS --verbose do appraisal contrib-old rake test:sidekiq'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails30-postgres rake test:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails30-postgres rake test:railsdisableenv'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails32-mysql2 rake test:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails32-postgres rake test:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails32-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails32-postgres rake test:railsdisableenv'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-mysql2 rake test:rails'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres rake test:rails'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres rake test:railsdisableenv'
    sh 'rvm $RAILS3_SIDEKIQ_VERSIONS --verbose do appraisal rails30-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS3_SIDEKIQ_VERSIONS --verbose do appraisal rails32-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS4_SIDEKIQ_VERSIONS --verbose do appraisal rails4-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS4_SIDEKIQ_VERSIONS --verbose do appraisal rails4-postgres-sidekiq rake test:railsactivejob'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-mysql2 rake test:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres rake test:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-sidekiq rake test:railsactivejob'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres rake test:railsdisableenv'
    # RSpec
    sh 'rvm $LAST_STABLE --verbose do rake benchmark'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails30-postgres rake spec:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails32-mysql2 rake spec:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails32-postgres rake spec:rails'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-mysql2 rake spec:rails'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres rake spec:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-mysql2 rake spec:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres rake spec:rails'
  else
    puts 'Too many workers than parallel tasks'
  end
end

task default: :test
