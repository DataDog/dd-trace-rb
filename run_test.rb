1000.times do |i|
  tests_passed = system('BUNDLE_GEMFILE=/app/gemfiles/jruby_9.2_contrib.gemfile bundle exec rspec ./spec/datadog/tracing/contrib/sucker_punch/patcher_spec.rb')
  break unless tests_passed
end
