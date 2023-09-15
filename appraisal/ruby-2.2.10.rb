appraise 'rails32-mysql2' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'mysql2', '0.3.21'
  gem 'activerecord-mysql-adapter'
  gem 'rack-cache', '1.7.1'
  gem 'sqlite3', '~> 1.3.5'
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

appraise 'rails4-postgres-sidekiq' do
  gem 'rails', '4.2.11.1'
  gem 'pg', '< 1.0'
  gem 'sidekiq'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-mysql2' do
  gem 'rails', '5.2.3'
  gem 'mysql2', '< 1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
end

appraise 'rails5-postgres' do
  gem 'rails', '5.2.3'
  gem 'pg', '< 1.0'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
end

appraise 'rails5-postgres-redis' do
  gem 'rails', '5.2.3'
  gem 'pg', '< 1.0'
  gem 'redis', '>= 4.0.1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
end

appraise 'rails5-postgres-redis-activesupport' do
  gem 'rails', '5.2.3'
  gem 'pg', '< 1.0'
  gem 'redis', '>= 4.0.1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
  gem 'redis-rails'
end

appraise 'rails5-postgres-sidekiq' do
  gem 'rails', '5.2.3'
  gem 'pg', '< 1.0'
  gem 'sidekiq', '~> 5.0'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
end

appraise 'rails5-semantic-logger' do
  gem 'rails', '5.2.3'
  gem 'pg', '< 1.0'
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
  gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
end

appraise 'aws' do
  gem 'aws-sdk'
  gem 'shoryuken'
end

appraise 'http' do
  gem 'elasticsearch'
  gem 'ethon'
  gem 'excon'
  gem 'faraday'
  gem 'multipart-post', '~> 2.1.1' # Compatible with faraday 0.x
  gem 'http'
  gem 'httpclient'
  gem 'rest-client'
  gem 'typhoeus'
end

appraise 'relational_db' do
  gem 'activerecord', '< 5.1.5'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
  gem 'mysql2', '< 0.5'
  gem 'pg', '>= 0.18.4'
  gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
  gem 'sqlite3', '~> 1.3.6'
end

appraise 'activesupport' do
  gem 'activesupport'

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
  gem 'dalli', '< 3.0.0' # Dalli 3.0 dropped support for Ruby < 2.5
  gem 'graphql'
  gem 'grpc', '~> 1.19.0' # Last version to support Ruby < 2.3 & google-protobuf < 3.7
  gem 'mongo', '>= 2.8.0'
  gem 'presto-client', '>=  0.5.14'
  gem 'rack', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
  gem 'rack-contrib'
  gem 'rack-test'
  gem 'rake', '>= 12.3'
  gem 'redis', '~> 3'
  gem 'resque', '< 2.0'
  gem 'roda', '>= 2.0.0'
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq'
  gem 'sneakers', '>= 2.12.0'
  gem 'sucker_punch'
  gem 'que', '>= 1.0.0', '< 2.0.0'
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
