require 'resque'

Resque.redis = ENV['REDIS_URL']
# Resque.redis = 'redis:6379' # Ruby 2.2 compatibility
