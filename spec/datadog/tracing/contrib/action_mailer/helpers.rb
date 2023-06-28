require 'rails'

RSpec.shared_context 'ActionMailer helpers' do
  before do
    # internal to tests only as instrumentatioin relies on ASN
    # but we patch here to ensure emails dont actually get set.
    # older rubies may have this live on `DeliveryJob` instead of `Base`
    # https://github.com/rails/rails/blob/e43d0ddb0359858fdb93e86b158987da81698a3d/guides/source/testing.md#the-basic-test-case
    if ActionMailer::Base.respond_to?(:delivery_method)
      ActionMailer::Base.delivery_method = :test
    else
      ActionMailer::DeliveryJob.delivery_method = :test
    end

    stub_const(
      'UserMailer',
      Class.new(ActionMailer::Base) do
        default from: 'test@example.com'

        def test_mail(_arg)
          mail(
            to: 'test@example.com',
            body: 'sk test',
            subject: 'miniswan',
            bcc: 'test_a@example.com,test_b@example.com',
            cc: ['test_c@example.com', 'test_d@example.com']
          )
        end
      end
    )
  end
end
