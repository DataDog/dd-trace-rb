require 'sinatra'

class RackTestApp < Sinatra::Application
  get '/endpoint' do
    '1'
  end
end

