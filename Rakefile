require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << %w(test lib)
  task.test_files = FileList['test/**/*_test.rb']
end

task :default => :test
