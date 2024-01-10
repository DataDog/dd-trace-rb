appraise 'hanami-1' do
  gem 'rack'
  gem 'rack-test' # Dev dependencies for testing rack-based code
  gem 'hanami', '~> 1'
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

appraise 'rails4-postgres-sidekiq' do
  gem 'rails', '4.2.11.1'
  gem 'pg', '< 1.0'
  gem 'sidekiq'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-mysql2' do
  gem 'rails', '~> 5.2.1'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
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
  gem 'redis', '>= 4.0.1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-postgres-redis-activesupport' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'redis-store', '~> 1.9'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'redis-rails'
end

appraise 'rails5-postgres-sidekiq' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-mysql2' do
  gem 'rails', '~> 6.0.0'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
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
  gem 'redis', '>= 4.0.1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-postgres-redis-activesupport' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'redis-store', '~> 1.9'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'redis-rails'
end

appraise 'rails6-postgres-sidekiq' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-mysql2' do
  gem 'rails', '~> 6.1.0'
  gem 'mysql2', '~> 0.5', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
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
  gem 'redis', '>= 4.2.5'
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
  gem 'redis', '>= 4.0'
  gem 'resque', '>= 2.0'
end

appraise 'aws' do
  gem 'aws-sdk'
  gem 'shoryuken'
end

appraise 'http' do
  gem 'ethon'
  gem 'excon'
  gem 'faraday'
  gem 'http'
  gem 'httpclient'
  gem 'rest-client'
  gem 'stripe', '~> 7.0'
  gem 'typhoeus'
end

[2, 3].each do |n|
  appraise "opensearch-#{n}" do
    gem 'opensearch-ruby', "~> #{n}"
  end
end

[7, 8].each do |n|
  appraise "elasticsearch-#{n}" do
    gem 'elasticsearch', "~> #{n}"
  end
end

appraise 'relational_db' do
  gem 'activerecord', '~> 5'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'makara'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'pg', '>= 0.18.4', platform: :ruby
  gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
  gem 'sqlite3', '~> 1.4.1', platform: :ruby
end

appraise 'activesupport' do
  gem 'activesupport', '~> 5'

  gem 'actionpack'
  gem 'actionview'
  gem 'active_model_serializers', '>= 0.10.0'
  gem 'grape'
  gem 'lograge', '~> 0.11'
  gem 'racecar', '>= 0.3.5'
  gem 'ruby-kafka', '>= 0.7.10'
end

appraise 'contrib' do
  gem 'concurrent-ruby'
  gem 'dalli', '>= 3.0.0'
  gem 'graphql', '>= 2.0'
  gem 'grpc', platform: :ruby
  gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
  gem 'rack-test' # Dev dependencies for testing rack-based code
  gem 'rake', '>= 12.3'
  gem 'resque'
  gem 'roda', '>= 2.0.0'
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq'
  gem 'sneakers', '>= 2.12.0'
  gem 'bunny', '~> 2.19.0' # uninitialized constant OpenSSL::SSL::TLS1_3_VERSION for jruby, https://github.com/ruby-amqp/bunny/issues/645
  gem 'sucker_punch'
  gem 'que', '>= 1.0.0', '< 2.0.0'
end

[1, 2, 3].each do |n|
  appraise "rack-#{n}" do
    gem 'rack', "~> #{n}"
    gem 'rack-contrib'
    gem 'rack-test' # Dev dependencies for testing rack-based code
  end
end

appraise 'sinatra' do
  gem 'sinatra'
  gem 'rack-contrib'
  gem 'rack-test' # Dev dependencies for testing rack-based code
end

appraise 'opentracing' do
  gem 'opentracing', '>= 0.4.1'
end

[3, 4, 5].each do |n|
  appraise "redis-#{n}" do
    gem 'redis', "~> #{n}"
  end
end

appraise 'contrib-old' do
  gem 'dalli', '< 3.0.0'
  gem 'faraday', '0.17'
  gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
  gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0
  gem 'qless', '0.12.0'
end

appraise 'core-old' do
  gem 'dogstatsd-ruby', '~> 4'
end
