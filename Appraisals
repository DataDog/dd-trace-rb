if RUBY_VERSION < '2.4.0' && RUBY_PLATFORM != 'java'
  if RUBY_VERSION >= '1.9.1'
    appraise 'rails3-mysql2' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    end
  end

  if RUBY_VERSION >= '1.9.1'
    appraise 'rails3-postgres' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    end

    appraise 'rails3-postgres-redis' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
    end

    appraise 'rails3-postgres-sidekiq' do
      gem 'test-unit'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
    end
  end

  if RUBY_VERSION >= '2.1.10'
    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.7.1'
      gem 'mysql2', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.7.1'
      gem 'pg', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.7.1'
      gem 'pg', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis-rails'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.7.1'
      gem 'pg', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
    end
  end

  if RUBY_VERSION >= '2.2.2'
    appraise 'rails5-mysql2' do
      gem 'rails', '5.0.1'
      gem 'mysql2', platform: :ruby
    end

    appraise 'rails5-postgres' do
      gem 'rails', '5.0.1'
      gem 'pg', platform: :ruby
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '5.0.1'
      gem 'pg', platform: :ruby
      gem 'redis-rails'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '5.0.1'
      gem 'pg', platform: :ruby
      gem 'sidekiq'
      gem "activejob"
    end
  end
end

if RUBY_VERSION >= '2.2.2' && RUBY_PLATFORM != 'java'
  appraise 'contrib' do
    gem 'elasticsearch-transport'
    gem 'grape'
    gem 'rack'
    gem 'rack-test'
    gem 'redis'
    gem 'hiredis'
    gem 'sinatra'
    gem 'sqlite3'
    gem 'activerecord'
    gem 'sidekiq'
  end
else
  appraise 'contrib-old' do
    gem 'elasticsearch-transport'
    gem 'redis'
    gem 'hiredis'
    gem 'rack', '1.4.7'
    gem 'rack-test'
    gem 'sinatra', '1.4.5'
    gem 'sqlite3'
    gem 'activerecord', '3.2.22.5'
    gem 'sidekiq', '4.0.0'
  end
end
