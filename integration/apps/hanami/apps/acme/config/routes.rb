# Configure your routes here
# See: https://guides.hanamirb.org/routing/overview
#
# Example:
# get '/hello', to: ->(env) { [200, {}, ['Hello from Hanami!']] }

resources :books, only: [:index, :show]

get '/health', to: ->(env) { [204, {}, ['Hello from Hanami!']] }
