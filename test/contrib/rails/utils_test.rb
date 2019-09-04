require 'helper'

require 'ddtrace/contrib/action_view/utils'

class UtilsTest < ActiveSupport::TestCase
  setup do
    @default_base_template = Datadog.configuration[:rails][:template_base_path]
  end

  teardown do
    Datadog.configuration[:rails][:template_base_path] = @default_base_template
  end

  test 'normalize_template_name' do
    full_template_name = '/opt/rails/app/views/welcome/index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  test 'normalize_template_name_nil' do
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(nil)
    assert_nil(template_name)
  end

  test 'normalize_template_name_not_a_path' do
    full_template_name = 'index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  test 'normalize_template_name_without_views_prefix' do
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  test 'normalize_template_name_with_custom_prefix' do
    Datadog.configuration[:rails][:template_base_path] = 'custom/'
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  test 'normalize_template_wrong_usage' do
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name({})
    assert_equal(template_name, '{}')
  end
end
