lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

def self.gem_cucumber(version)
  appraise "cucumber#{version}" do
    gem 'cucumber', ">=#{version}.0.0", "<#{version + 1}.0.0"
  end
end

if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(Datadog::VERSION::MINIMUM_RUBY_VERSION)
  raise NotImplementedError, "Ruby versions < #{Datadog::VERSION::MINIMUM_RUBY_VERSION} are not supported!"
elsif Gem::Version.new('2.0.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '~> 1.3.5'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'contrib-old' do
      gem 'active_model_serializers', '~> 0.9.0'
      gem 'activerecord', '3.2.22.5'
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'aws-sdk', '~> 2.0'
      gem 'concurrent-ruby'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'ethon'
      gem 'excon'
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'pg', '< 1.0', platform: :ruby
      gem 'rack', '1.4.7'
      gem 'rack-cache', '1.7.1'
      gem 'rack-test', '0.7.0'
      gem 'rake', '< 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque', '< 2.0'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '~> 4.0', '< 4.37'
      gem 'sidekiq', '~> 3.5.4'
      gem 'sinatra', '1.4.5'
      gem 'sqlite3', '~> 1.3.6'
      gem 'sucker_punch'
      gem 'timers', '< 4.2'
      gem 'typhoeus'
    end
  end
elsif Gem::Version.new('2.1.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '~> 1.3.5'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.11.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'contrib-old' do
      gem 'active_model_serializers', '~> 0.9.0'
      gem 'activerecord', '3.2.22.5'
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'aws-sdk', '~> 2.0'
      gem 'concurrent-ruby'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'presto-client', '>=  0.5.14'
      gem 'ethon'
      gem 'excon'
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'pg', '< 1.0', platform: :ruby
      gem 'rack', '1.4.7'
      gem 'rack-cache', '1.7.1'
      gem 'rack-test', '0.7.0'
      gem 'rake', '< 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque', '< 2.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '~> 4.0', '< 4.37'
      gem 'shoryuken'
      gem 'sidekiq', '~> 3.5.4'
      gem 'sinatra', '1.4.5'
      gem 'sqlite3', '~> 1.3.6'
      gem 'sucker_punch'
      gem 'timers', '< 4.2'
      gem 'typhoeus'
    end
  end
elsif Gem::Version.new('2.2.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '~> 1.3.5'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.11.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '5.2.3'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '5.2.3'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '5.2.3'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '5.2.3'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '5.2.3'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord', '< 5.1.5'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'pg', platform: :ruby
      gem 'presto-client', '>=  0.5.14'
      gem 'ethon'
      gem 'excon'
      gem 'faraday'
      gem 'grape'
      gem 'graphql', '< 1.9.4'
      gem 'grpc', '~> 1.21.0' # Last version to support Ruby < 2.3
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'qless'
      gem 'racecar', '>= 0.3.5'
      gem 'rack', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque', '< 2.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel'
      gem 'shoryuken'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.3.6'
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0.beta2'
    end
  end
elsif Gem::Version.new('2.3.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '~> 1.3.5'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
      gem 'lograge', '< 0.4'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.11.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..4).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord', '< 5.1.5'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'ethon'
      gem 'excon'
      gem 'faraday'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'google-protobuf', '~> 3.11.0' # Last version to support Ruby < 2.5
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'pg', platform: :ruby
      gem 'presto-client', '>=  0.5.14'
      gem 'qless'
      gem 'racecar', '>= 0.3.5'
      gem 'rack', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel'
      gem 'shoryuken'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.3.6'
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end
  end
elsif Gem::Version.new('2.4.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..4).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord', '< 5.1.5'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'cucumber'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'ethon'
      gem 'excon'
      gem 'faraday'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'google-protobuf', '~> 3.11.0' # Last version to support Ruby < 2.5
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'pg', platform: :ruby
      gem 'presto-client', '>=  0.5.14'
      gem 'qless'
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel'
      gem 'shoryuken'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.3.6'
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end
  end
elsif Gem::Version.new('2.5.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.6.0')
  appraise 'rails5-mysql2' do
    gem 'rails', '~> 5.2.1'
    gem 'mysql2', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails5-postgres' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails5-postgres-redis' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails5-postgres-redis-activesupport' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails5-postgres-sidekiq' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sidekiq'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails6-mysql2' do
    gem 'rails', '~> 6.0.0'
    gem 'mysql2', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 60', platform: :jruby # try remove >= 60
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails6-postgres' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails6-postgres-redis' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails6-postgres-redis-activesupport' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails6-postgres-sidekiq' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sidekiq'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge'
  end

  appraise 'rails61-mysql2' do
    gem 'rails', '~> 6.1.0'
    gem 'mysql2', '~> 0.5', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails61-postgres' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails61-postgres-redis' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'redis', '>= 4.2.5'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails61-postgres-sidekiq' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sidekiq', '>= 6.1.2'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'resque2-redis3' do
    gem 'redis', '< 4.0'
    gem 'resque', '>= 2.0'
  end

  appraise 'resque2-redis4' do
    gem 'redis', '>= 4.0'
    gem 'resque', '>= 2.0'
  end

  (3..5).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack'
    gem 'actionview'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'cucumber'
    gem 'dalli'
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'elasticsearch-transport'
    gem 'ethon'
    gem 'excon'
    gem 'faraday'
    gem 'grape'
    gem 'graphql'
    gem 'grpc', platform: :ruby
    gem 'hiredis'
    gem 'http'
    gem 'mongo', '>= 2.8.0'
    gem 'mysql2', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 60.2', platform: :jruby
    gem 'pg', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60.2', platform: :jruby
    gem 'presto-client', '>=  0.5.14'
    gem 'qless'
    gem 'racecar', '>= 0.3.5'
    gem 'rack'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'redis', '< 4.0'
    gem 'rest-client'
    gem 'resque'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'sequel'
    gem 'shoryuken'
    gem 'sidekiq'
    gem 'sinatra'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '~> 1.4.1', platform: :ruby
    gem 'jdbc-sqlite3', '>= 3.28', platform: :jruby
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0.beta2'
  end

  appraise 'contrib-old' do
    gem 'faraday', '0.17'
  end
elsif Gem::Version.new('2.6.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-mysql2' do
      gem 'rails', '~> 6.0.0'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres-redis' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres-redis-activesupport' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres-sidekiq' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
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

    appraise 'resque2-redis3' do
      gem 'redis', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..5).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'cucumber'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'ethon'
      gem 'excon'
      gem 'faraday'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'pg', platform: :ruby
      gem 'presto-client', '>=  0.5.14'
      gem 'qless'
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel'
      gem 'shoryuken'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.4.1'
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end
  end
elsif Gem::Version.new('2.7.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis-rails'
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis-rails'
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-mysql2' do
      gem 'rails', '~> 6.0.0'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres-redis' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis-rails'
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres-redis-activesupport' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis-rails'
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge'
    end

    appraise 'rails6-postgres-sidekiq' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge'
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

    appraise 'resque2-redis3' do
      gem 'redis', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..5).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'cucumber'
      gem 'dalli'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch-transport'
      gem 'ethon'
      gem 'excon'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'hiredis'
      gem 'http'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'pg', platform: :ruby
      gem 'presto-client', '>=  0.5.14'
      gem 'qless'
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'rest-client'
      gem 'resque'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel'
      gem 'shoryuken'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.4.1'
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end
  end
elsif Gem::Version.new('3.0.0') <= Gem::Version.new(RUBY_VERSION)
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

  appraise 'resque2-redis3' do
    gem 'redis', '< 4.0'
    gem 'resque', '>= 2.0'
  end

  appraise 'resque2-redis4' do
    gem 'redis', '>= 4.0'
    gem 'resque', '>= 2.0'
  end

  (3..5).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack'
    gem 'actionview'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'cucumber'
    gem 'dalli'
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'elasticsearch-transport'
    gem 'ethon'
    gem 'excon'
    gem 'grape'
    gem 'graphql'
    # gem 'grpc' # Pending 3.0 support by transient protobuf dependency https://github.com/protocolbuffers/protobuf/issues/7922
    gem 'hiredis'
    gem 'http'
    gem 'mongo', '>= 2.8.0'
    gem 'mysql2', '>= 0.5.3', platform: :ruby
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'presto-client', '>=  0.5.14'
    gem 'qless'
    # gem 'racecar', '>= 0.3.5' # Pending release of our fix: https://github.com/appsignal/rdkafka-ruby/pull/144
    gem 'rack'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'redis', '< 4.0'
    gem 'rest-client'
    gem 'resque'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'sequel'
    gem 'shoryuken'
    gem 'sidekiq'
    gem 'sinatra'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '>= 1.4.2'
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0.beta2'
  end
end
