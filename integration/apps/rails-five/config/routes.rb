Rails.application.routes.draw do
  get '/', to: 'basic#default'
  get 'health', to: 'health#check'
  get 'health/detailed', to: 'health#detailed_check'

  # Basic test scenarios
  get 'basic/default', to: 'basic#default'
  get 'basic/fibonacci', to: 'basic#fibonacci'

  get 'di/ar_serializer', to: 'di#ar_serializer'

  # Job test scenarios
  post 'jobs', to: 'jobs#create'
end
