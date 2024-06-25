Rake::Task["build"].enhance(["build:pre_check"])
Rake::Task["build"].enhance do
  # This syntax makes this task run after build -- see https://dev.to/molly/rake-task-enhance-method-explained-3bo0
  Rake::Task["build:after_check"].execute
end

desc 'Checks executed before gem is built'
task :'build:pre_check' do
  require 'rspec'
  RSpec.world.reset # If any other tests ran before, flushes them
  ret = RSpec::Core::Runner.run(['spec/datadog/release_gem_spec.rb'])
  raise "Release tests failed! See error output above." if ret != 0
end

desc 'Checks executed after gem is built'
task :'build:after_check' do
  require 'rspec'
  RSpec.world.reset # If any other tests ran before, flushes them
  ret = RSpec::Core::Runner.run(['spec/datadog/gem_packaging_spec.rb'])
  raise "Release tests failed! See error output above." if ret != 0
end

desc 'Create a new indexed repository'
task :'release:gem' do
  raise 'Missing environment variable S3_DIR' if !S3_DIR || S3_DIR.empty?
  # load existing deployed gems
  sh "aws s3 cp --exclude 'docs/*' --recursive s3://#{S3_BUCKET}/#{S3_DIR}/ ./rubygems/"

  # create folders
  sh 'mkdir -p ./gems'
  sh 'mkdir -p ./rubygems/gems'

  # build the gem
  Rake::Task['build'].execute

  # copy the output in the indexed folder
  sh 'cp pkg/*.gem ./rubygems/gems/'

  # generate the gems index
  sh 'gem generate_index -v --no-modern -d ./rubygems'

  # remove all local repository gems to limit files needed to be uploaded
  sh 'rm -f ./rubygems/gems/*'

  # re-add new gems
  sh 'cp pkg/*.gem ./rubygems/gems/'

  # deploy a static gem registry
  sh "aws s3 cp --recursive ./rubygems/ s3://#{S3_BUCKET}/#{S3_DIR}/"
end
