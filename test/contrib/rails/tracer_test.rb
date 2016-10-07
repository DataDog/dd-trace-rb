require 'contrib/rails/test_helper'

class WelcomeControllerTest < ActionController::TestCase
  test 'the app should be initialized' do
    get :index
    assert_response :success
  end
end
