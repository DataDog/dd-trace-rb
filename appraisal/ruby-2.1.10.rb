appraise 'rails32-mysql2' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'mysql2', '0.3.21'
  gem 'activerecord-mysql-adapter'
  gem 'rack-cache', '1.7.1'
  gem 'sqlite3', '~> 1.3.5'
  gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
end

appraise 'rails32-postgres' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'pg', '0.15.1'
  gem 'rack-cache', '1.7.1'
end

appraise 'rails32-postgres-redis' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'pg', '0.15.1'
  gem 'redis-rails'
  gem 'redis', '< 4.0'
  gem 'rack-cache', '1.7.1'
end

appraise 'rails32-postgres-sidekiq' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'pg', '0.15.1'
  gem 'sidekiq', '4.0.0'
  gem 'rack-cache', '1.7.1'
  gem 'connection_pool', '2.2.3'
end

appraise 'rails4-mysql2' do
  gem 'rails', '4.2.11.1'
  gem 'mysql2', '< 1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails4-postgres' do
  gem 'rails', '4.2.11.1'
  gem 'pg', '< 1.0'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails4-semantic-logger' do
  gem 'rails', '4.2.11.1'
  gem 'pg', '< 1.0'
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
end

appraise 'rails4-postgres-redis' do
  gem 'rails', '4.2.11.1'
  gem 'pg', '< 1.0'
  gem 'redis-rails'
  gem 'redis', '< 4.0'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'aws' do
  gem 'aws-sdk', '~> 2.0'
end

appraise 'http' do
  gem 'elasticsearch'
  gem 'faraday'
  gem 'multipart-post', '~> 2.1.1' # Compatible with faraday 0.x
  gem 'ethon'
  gem 'excon'
  gem 'http'
  gem 'httpclient'
  gem 'rest-client'
  gem 'typhoeus'
end

appraise 'relational_db' do
  gem 'activerecord', '3.2.22.5'
  gem 'activerecord-mysql-adapter'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
  gem 'mysql2', '0.3.21'
  gem 'pg', '>= 0.18.4', '< 1.0'
  gem 'sequel', '~> 4.0', '< 4.37'
  gem 'sqlite3', '~> 1.3.6'
end

appraise 'contrib' do
  gem 'active_model_serializers', '~> 0.9.0'
  gem 'concurrent-ruby'
  gem 'dalli', '< 3.0.0' # Dalli 3.0 dropped support for Ruby < 2.5
  gem 'presto-client', '>=  0.5.14'
  gem 'mongo', '< 2.5'
  gem 'rack', '1.4.7'
  gem 'rack-contrib'
  gem 'rack-cache', '1.7.1'
  gem 'rack-test', '0.7.0'
  gem 'rake', '< 12.3'
  gem 'resque', '< 2.0'
  gem 'roda', '>= 2.0.0'
  gem 'ruby-kafka', '>= 0.7.10'
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq', '~> 3.5.4'
  gem 'sucker_punch'
  gem 'timers', '< 4.2'
end

[1].each do |n|
  appraise "rack-#{n}" do
    gem 'rack', "~> #{n}"
    gem 'rack-contrib'
    gem 'rack-test'
  end
end

appraise 'sinatra' do
  gem 'sinatra'
  gem 'rack-test'
end

[3].each do |n|
  appraise "redis-#{n}" do
    gem 'redis', "~> #{n}"
  end
end

appraise 'core-old' do
  gem 'dogstatsd-ruby', '~> 4'
end
