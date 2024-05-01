require 'resque'

Resque.redis = ENV['REDIS_URL']
