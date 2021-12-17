combination 'rails', '>= 3.2.22.5', minor: true do
  combination 'mysql' do
    gem 'mysql2', '0.3.21'
    gem 'activerecord-mysql-adapter'
    gem 'sqlite3', '~> 1.3.5'
    gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
  end

  combination 'pg' do
    if version('rails') < '4.0' # can I do this??
      gem 'pg', '0.15.1'
    else
      gem 'pg', '< 1.0'
    end
  end

  gem 'rack-cache', '1.7.1'
  gem 'test-unit'
end

# rails32-mysql2
gem 'test-unit'
gem 'rails', '3.2.22.5'
gem 'mysql2', '0.3.21'
gem 'activerecord-mysql-adapter'
gem 'rack-cache', '1.7.1'
gem 'sqlite3', '~> 1.3.5'
gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax

# rails32-postgres
gem 'pg', '0.15.1'

# rails32-postgres-redis
gem 'pg', '0.15.1'
gem 'redis-rails'
gem 'redis', '< 4.0'

# rails32-postgres-sidekiq
gem 'pg', '0.15.1'
gem 'sidekiq', '4.0.0'

# rails4-mysql2
gem 'rails', '4.2.11.1'
gem 'mysql2', '< 1'
gem 'sprockets', '< 4'
gem 'lograge', '~> 0.11'

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
