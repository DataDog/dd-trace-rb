require 'bundler/gem_tasks'
require 'rubocop/rake_task'
require 'rake/testtask'
require 'rdoc/task'
require 'appraisal'

Rake::TestTask.new(:test) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/**/*_test.rb'].reject do |path|
    path.include?('contrib')
  end
end

Rake::TestTask.new(:rails) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/contrib/rails/**/*_test.rb']
end

Rake::TestTask.new(:contrib) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/contrib/**/*_test.rb'].reject do |path|
    path.include?('rails') || path.include?('autopatch_test.rb')
  end
end

Rake::TestTask.new(:autopatch) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/contrib/autopatch_test.rb']
end

Rake::TestTask.new(:benchmark) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/benchmark_test.rb']
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'Gemfile', 'Rakefile']
end

RDoc::Task.new(:rdoc) do |doc|
  doc.main   = 'docs/GettingStarted'
  doc.title  = 'Datadog Ruby Tracer'
  # TODO[manu]: include all lib/ folder, but only when all classes' docs are ready
  doc.rdoc_files = FileList.new(%w(lib/ddtrace/tracer.rb lib/ddtrace/span.rb docs/**/*))
  doc.rdoc_dir = 'html'
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
task :'release:docs' => :rdoc do
  raise 'Missing environment variable S3_DIR' if !S3_DIR || S3_DIR.empty?
  sh "aws s3 cp --recursive html/ s3://#{S3_BUCKET}/#{S3_DIR}/docs/"
end

task default: :test
