require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task' if RUBY_VERSION >= '2.1.0'
require 'rake/testtask'
require 'appraisal'
require 'yard'

namespace :test do
  task all: [:main,
             :rails, :railsredis, :railssidekiq, :railsactivejob,
             :elasticsearch, :http, :redis, :sidekiq, :sinatra, :monkey]

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
        path.include?('active_job')
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

  [:elasticsearch, :http, :redis, :sinatra, :sidekiq, :rack, :grape].each do |contrib|
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
    sh 'rvm $LAST_STABLE --verbose do rake benchmark'
  when 1
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:elasticsearch'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:http'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:redis'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sinatra'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sidekiq'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:rack'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:grape'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:monkey'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:elasticsearch'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:http'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:redis'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:sinatra'
    sh 'rvm $MRI_OLD_VERSIONS --verbose do appraisal contrib-old rake test:rack'
    sh 'rvm $SIDEKIQ_OLD_VERSIONS --verbose do appraisal contrib-old rake test:sidekiq'
  when 2
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails3-mysql2 rake test:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails3-postgres rake test:rails'
    sh 'rvm $RAILS3_VERSIONS --verbose do appraisal rails3-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-mysql2 rake test:rails'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres rake test:rails'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres-redis rake test:railsredis'
    # Test Rails3/Sidekiq with Rails4 versions (3 vs 4) as Sidekiq requires >= 2.0 and Rails3 should support 1.9
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails3-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS4_VERSIONS --verbose do appraisal rails4-postgres-sidekiq rake test:railsactivejob'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-mysql2 rake test:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres rake test:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-sidekiq rake test:railssidekiq'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-sidekiq rake test:railsactivejob'
  else
    puts 'Too many workers than parallel tasks'
  end
end

task default: :test
