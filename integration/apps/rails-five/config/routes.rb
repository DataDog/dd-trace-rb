Rails.application.routes.draw do
  get '/', to: 'basic#default'
  get 'health', to: 'health#check'
  get 'health/profiling', to: 'health#profiling_check'

  # Basic test scenarios
  get 'basic/default', to: 'basic#default'
  get 'basic/fibonacci', to: 'basic#fibonacci'

  # Job test scenarios
  post 'jobs', to: 'jobs#create'
end
