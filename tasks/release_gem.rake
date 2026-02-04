Rake::Task["build"].enhance(["build:pre_check"])
Rake::Task["build"].enhance do
  # This syntax makes this task run after build -- see https://dev.to/molly/rake-task-enhance-method-explained-3bo0
  Rake::Task["build:after_check"].execute
end

desc 'Checks executed before gem is built'
task :"build:pre_check" do
  require 'rspec'
  RSpec.world.reset # If any other tests ran before, flushes them
  ret = RSpec::Core::Runner.run(['spec/datadog/release_gem_spec.rb'])
  raise "Release tests failed! See error output above." if ret != 0
end

desc 'Checks executed after gem is built'
task :"build:after_check" do
  require 'rspec'
  RSpec.world.reset # If any other tests ran before, flushes them
  ret = RSpec::Core::Runner.run(['spec/datadog/gem_packaging_spec.rb'])
  raise "Release tests failed! See error output above." if ret != 0
end
