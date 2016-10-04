require 'bundler/gem_tasks'
require 'rubocop/rake_task'
require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << %w(test lib)
  task.test_files = FileList['test/**/*_test.rb']
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'Gemfile', 'Rakefile']
end

task default: :test
