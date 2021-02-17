source 'https://rubygems.org'

gemspec

# Development dependencies
gem 'addressable', '~> 2.4.0' # locking transitive dependency of webmock
gem 'appraisal', '~> 2.2'
gem 'benchmark-ips', '~> 2.8'
gem 'benchmark-memory', '~> 0.1'
gem 'builder'
gem 'climate_control', '~> 0.2.0'
gem 'concurrent-ruby' # Leave it open; it's integration too, and we want Appraisal to set the version.
gem 'memory_profiler', '~> 0.9'
gem 'minitest', '= 5.10.1'
gem 'minitest-around', '0.5.0'
gem 'minitest-stub_any_instance', '1.0.2'
gem 'pimpmychangelog', '>= 0.1.2'
gem 'pry', '~> 0.12.2'
gem 'pry-nav', '~> 0.3.0'
gem 'pry-stack_explorer', '~> 0.4.9' if RUBY_PLATFORM != 'java'
gem 'rake', '>= 10.5'
gem 'redcarpet', '~> 3.4' if RUBY_PLATFORM != 'java'
gem 'rspec', '~> 3.0'
gem 'rspec-collection_matchers', '~> 1.1'
gem 'rspec_junit_formatter', '>= 0.4.1'
gem 'rspec_n', '~> 1.3' if RUBY_VERSION >= '2.3.0'
gem 'rubocop', '= 0.50.0' if RUBY_VERSION >= '2.1.0'
gem 'ruby-prof', '~> 1.4' if RUBY_PLATFORM != 'java' && RUBY_VERSION >= '2.4.0'
gem 'simplecov', '~> 0.17'
gem 'warning', '~> 1' if RUBY_VERSION >= '2.5.0'
gem 'webmock', '>= 3.10.0'
gem 'webrick', '>= 1.7.0' if RUBY_VERSION >= '3.0.0' # No longer bundled by default since Ruby 3.0
gem 'yard', '~> 0.9'

# Optional extensions
# TODO: Move this to Appraisals?
gem 'dogstatsd-ruby', '>= 3.3.0'
gem 'opentracing', '>= 0.4.1'
