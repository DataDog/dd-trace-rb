if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('1.9.3')
  raise NotImplementedError, 'Ruby versions < 1.9.3 are not supported!'
elsif Gem::Version.new('1.9.3') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'contrib-old' do
      gem 'active_model_serializers', '~> 0.9.0'
      gem 'activerecord', '3.2.22.5'
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'aws-sdk', '~> 2.0'
      gem 'dalli'
      gem 'elasticsearch'
      gem 'excon'
      gem 'hiredis'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'rack', '1.4.7'
      gem 'rack-cache', '1.7.1'
      gem 'rack-test', '0.7.0'
      gem 'rake', '< 12.3'
      gem 'redis', '< 4.0'
      gem 'resque', '< 2.0'
      gem 'sequel', '~> 4.0', '< 4.37'
      gem 'sidekiq', '4.0.0'
      gem 'sinatra', '1.4.5'
      gem 'sqlite3'
      gem 'sucker_punch'
    end
  end
elsif Gem::Version.new('2.0.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'contrib-old' do
      gem 'active_model_serializers', '~> 0.9.0'
      gem 'activerecord', '3.2.22.5'
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'aws-sdk', '~> 2.0'
      gem 'dalli'
      gem 'elasticsearch'
      gem 'excon'
      gem 'hiredis'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'rack', '1.4.7'
      gem 'rack-cache', '1.7.1'
      gem 'rack-test', '0.7.0'
      gem 'rake', '< 12.3'
      gem 'redis', '< 4.0'
      gem 'resque', '< 2.0'
      gem 'sequel', '~> 4.0', '< 4.37'
      gem 'sidekiq', '4.0.0'
      gem 'sinatra', '1.4.5'
      gem 'sqlite3'
      gem 'sucker_punch'
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
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.7.1'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
    end

    appraise 'contrib-old' do
      gem 'active_model_serializers', '~> 0.9.0'
      gem 'activerecord', '3.2.22.5'
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'aws-sdk', '~> 2.0'
      gem 'dalli'
      gem 'elasticsearch'
      gem 'excon'
      gem 'hiredis'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'rack', '1.4.7'
      gem 'rack-cache', '1.7.1'
      gem 'rack-test', '0.7.0'
      gem 'rake', '< 12.3'
      gem 'redis', '< 4.0'
      gem 'resque', '< 2.0'
      gem 'sequel', '~> 4.0', '< 4.37'
      gem 'sidekiq', '4.0.0'
      gem 'sinatra', '1.4.5'
      gem 'sqlite3'
      gem 'sucker_punch'
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
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.7.1'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.1.6'
      gem 'mysql2', '< 0.5', platform: :ruby
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.1.6'
      gem 'pg', '< 1.0', platform: :ruby
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.1.6'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis-rails'
      gem 'redis'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.1.6'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
    end

    appraise 'contrib' do
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord', '< 5.1.5'
      gem 'aws-sdk'
      gem 'dalli'
      gem 'elasticsearch'
      gem 'excon'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'hiredis'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'resque', '< 2.0'
      gem 'sequel'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sqlite3'
      gem 'sucker_punch'
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
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.7.1'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
      gem 'redis', '< 4.0'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.7.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.1.6'
      gem 'mysql2', '< 0.5', platform: :ruby
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.1.6'
      gem 'pg', '< 1.0', platform: :ruby
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.1.6'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis-rails'
      gem 'redis'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.1.6'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq'
      gem 'activejob'
    end

    appraise 'contrib' do
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord', '< 5.1.5'
      gem 'aws-sdk'
      gem 'dalli'
      gem 'elasticsearch'
      gem 'excon'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'hiredis'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'resque', '< 2.0'
      gem 'sequel'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sqlite3'
      gem 'sucker_punch'
    end
  end
elsif Gem::Version.new('2.4.0') <= Gem::Version.new(RUBY_VERSION)
  if RUBY_PLATFORM != 'java'
    appraise 'contrib' do
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord', '< 5.1.5'
      gem 'aws-sdk'
      gem 'dalli'
      gem 'elasticsearch'
      gem 'excon'
      gem 'grape'
      gem 'graphql'
      gem 'grpc'
      gem 'hiredis'
      gem 'mongo', '< 2.5'
      gem 'mysql2', '< 0.5', platform: :ruby
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '< 4.0'
      gem 'resque', '< 2.0'
      gem 'sequel'
      gem 'sidekiq'
      gem 'sinatra'
      gem 'sqlite3'
      gem 'sucker_punch'
    end
  end
end
