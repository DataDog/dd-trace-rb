require 'bundler/gem_tasks'
require 'rubocop/rake_task'
require 'rake/testtask'
require 'rdoc/task'
require 'appraisal'

Rake::TestTask.new(:test) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/**/*_test.rb'].reject do |path|
    path.include?('rails')
  end
end

Rake::TestTask.new(:rails) do |t|
  t.libs << %w(test lib)
  t.test_files = FileList['test/contrib/rails/**/*_test.rb']
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'Gemfile', 'Rakefile']
end

RDoc::Task.new(:rdoc) do |doc|
  doc.main   = 'docs/Getting_started.rdoc'
  doc.title  = 'Datadog Ruby Tracer'
  doc.rdoc_files = FileList.new %w[lib docs/**/*.rdoc *.rdoc]
  doc.rdoc_dir = 'html'
end

task default: :test
