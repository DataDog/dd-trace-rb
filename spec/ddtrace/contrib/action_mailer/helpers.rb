require 'rails'

RSpec.shared_context 'ActionMailer helpers' do
  
  before(:each) do
    if ActionMailer::Base.respond_to?(:delivery_method)
      ActionMailer::Base.delivery_method  = :test
    else
      ActionMailer::DeliveryJob.delivery_method = :test
    end

    stub_const(
      "UserMailer",
      Class.new(ActionMailer::Base) do
        default from: "test@example.com"

        def test_mail(_arg)
          mail(to: "test@example.com", body: "sk test")
        end
      end
    )
  end
end