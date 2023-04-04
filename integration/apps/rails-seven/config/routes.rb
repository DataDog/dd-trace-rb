Rails.application.routes.draw do
  match '/500', via: :all, to: 'errors#server_error'

  get '/', to: 'basic#default'
  get 'health', to: 'health#check'
  get 'health/detailed', to: 'health#detailed_check'

  # Basic test scenarios
  get 'basic/default', to: 'basic#default'
  get 'basic/fibonacci', to: 'basic#fibonacci'
  get 'basic/boom', to: 'basic#boom'

  # Job test scenarios
  post 'jobs', to: 'jobs#create'
end
