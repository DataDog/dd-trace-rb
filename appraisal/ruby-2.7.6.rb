appraise 'hanami-1' do
  gem 'rack'
  gem 'rack-test'
  gem 'hanami', '~> 1'
end

appraise 'rails5-mysql2' do
  gem 'rails', '~> 5.2.1'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-postgres' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-semantic-logger' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
end

appraise 'rails5-postgres-redis' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-postgres-redis-activesupport' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'redis-rails'
  gem 'redis-store', '>= 1.4', '< 2'
end

appraise 'rails5-postgres-sidekiq' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-mysql2' do
  gem 'rails', '~> 6.0.0'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-postgres' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-semantic-logger' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
end

appraise 'rails6-postgres-redis' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-postgres-redis-activesupport' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'redis-rails'
  gem 'redis-store', '>= 1.4', '< 2'
end

appraise 'rails6-postgres-sidekiq' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-mysql2' do
  gem 'rails', '~> 6.1.0'
  gem 'mysql2', '~> 0.5', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-postgres' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-postgres-redis' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-postgres-sidekiq' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sidekiq', '>= 6.1.2'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-semantic-logger' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
end

appraise 'resque2-redis3' do
  gem 'redis', '< 4.0'
  gem 'resque', '>= 2.0'
end

appraise 'resque2-redis4' do
  gem 'redis', '~> 4.0'
  gem 'resque', '>= 2.0'
end

(3..8).each { |v| gem_cucumber(v) }

appraise 'aws' do
  gem 'aws-sdk'
  gem 'shoryuken'
end

appraise 'http' do
  gem 'elasticsearch'
  gem 'ethon'
  gem 'excon'
  gem 'faraday'
  gem 'http'
  gem 'httpclient'
  gem 'opensearch-ruby'
  gem 'rest-client'
  gem 'stripe'
  gem 'typhoeus'
end

appraise 'contrib' do
  gem 'actionpack'
  gem 'actionview'
  gem 'active_model_serializers', '>= 0.10.0'
  gem 'activerecord', '~> 6.1.0'
  gem 'concurrent-ruby'
  gem 'dalli', '>= 3.0.0'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'grape'
  gem 'graphql', '>= 2.0'
  gem 'grpc'
  gem 'lograge', '~> 0.11'
  gem 'makara'
  gem 'minitest', '>= 5.0.0'
  gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
  gem 'mysql2', '< 1', platform: :ruby
  gem 'pg', '>= 0.18.4', platform: :ruby
  gem 'racecar', '>= 0.3.5'
  gem 'rack'
  gem 'rack-contrib'
  gem 'rack-test'
  gem 'rake', '>= 12.3'
  gem 'resque'
  gem 'roda', '>= 2.0.0'
  gem 'ruby-kafka', '>= 0.7.10'
  gem 'rspec', '>= 3.0.0'
  gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
  gem 'sneakers', '>= 2.12.0'
  gem 'sqlite3', '~> 1.4.1'
  gem 'sucker_punch'
  gem 'que', '>= 1.0.0'
end

[1, 2, 3].each do |n|
  appraise "rack-#{n}" do
    gem 'rack', "~> #{n}"
    gem 'rack-contrib'
    gem 'rack-test'
  end
end

appraise 'sinatra' do
  gem 'sinatra', '>= 3'
  gem 'rack-test'
end

appraise 'opentelemetry' do
  gem 'opentelemetry-sdk', '~> 1.1'
end

[3, 4, 5].each do |n|
  appraise "redis-#{n}" do
    gem 'redis', "~> #{n}"
  end
end

appraise 'contrib-old' do
  gem 'dalli', '< 3.0.0'
  gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
  gem 'faraday', '0.17'
  gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
  gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0
  gem 'qless', '0.12.0'
end

appraise 'core-old' do
  gem 'dogstatsd-ruby', '~> 4'
end
