require 'sinatra/base'
require 'ddtrace'
require 'request_store'

class Parent < Sinatra::Base
  use ::RequestStore::Middleware
end
