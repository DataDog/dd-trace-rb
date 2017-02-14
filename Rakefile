require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task'
require 'rake/testtask'
require 'appraisal'
require 'yard'

namespace :test do
  task all: [:main, :rails, :railsredis, :elasticsearch, :http, :redis, :sinatra, :monkey]

  Rake::TestTask.new(:main) do |t|
    t.libs << %w(test lib)
    t.test_files = FileList['test/**/*_test.rb'].reject do |path|
      path.include?('contrib') ||
        path.include?('benchmark') ||
        path.include?('redis') ||
        path.include?('monkey_test.rb')
    end
  end

  Rake::TestTask.new(:rails) do |t|
    t.libs << %w(test lib)
    t.test_files = FileList['test/contrib/rails/**/*_test.rb'].reject do |path|
      path.include?('redis')
    end
  end

  Rake::TestTask.new(:railsredis) do |t|
    t.libs << %w(test lib)
    t.test_files = FileList['test/contrib/rails/**/*redis*_test.rb']
  end

  [:elasticsearch, :http, :redis, :sinatra].each do |contrib|
    Rake::TestTask.new(contrib) do |t|
      t.libs << %w(test lib)
      t.test_files = FileList["test/contrib/#{contrib}/*_test.rb"]
    end
  end

  Rake::TestTask.new(:monkey) do |t|
    t.libs << %w(test lib)
    t.test_files = FileList['test/monkey_test.rb']
  end
end

Rake::TestTask.new(:benchmark) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/benchmark_test.rb']
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'Gemfile', 'Rakefile']
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
    sh 'rvm $MRI_VERSIONS --verbose do rake test:main'
    sh 'rvm $LAST_STABLE --verbose do rake benchmark'
  when 1
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:monkey'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:elasticsearch'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:http'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:redis'
    sh 'rvm $MRI_VERSIONS --verbose do appraisal contrib rake test:sinatra'
  when 2
    sh 'rvm $RAILS_VERSIONS --verbose do appraisal rails3-postgres rake test:rails'
    sh 'rvm $RAILS_VERSIONS --verbose do appraisal rails3-mysql2 rake test:rails'
    sh 'rvm $RAILS_VERSIONS --verbose do appraisal rails4-postgres rake test:rails'
    sh 'rvm $RAILS_VERSIONS --verbose do appraisal rails4-mysql2 rake test:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres rake test:rails'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-mysql2 rake test:rails'
    sh 'rvm $RAILS_VERSIONS --verbose do appraisal rails3-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS_VERSIONS --verbose do appraisal rails4-postgres-redis rake test:railsredis'
    sh 'rvm $RAILS5_VERSIONS --verbose do appraisal rails5-postgres-redis rake test:railsredis'
  else
    puts 'Too many workers than parallel tasks'
  end
end

task default: :test
