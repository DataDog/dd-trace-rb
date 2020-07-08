require 'helper'
require 'ddtrace'

class UtilsTest < Minitest::Test
  def setup
    @default_base_template = Datadog.configuration[:rails][:template_base_path]
  end

  def teardown
    Datadog.configuration[:rails][:template_base_path] = @default_base_template
  end

  def test_normalize_template_name
    full_template_name = '/opt/rails/app/views/welcome/index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  def test_normalize_template_name_nil
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(nil)
    assert_nil(template_name)
  end

  def test_normalize_template_name_not_a_path
    full_template_name = 'index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  def test_normalize_template_name_without_views_prefix
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  def test_normalize_template_name_with_custom_prefix
    Datadog.configuration[:rails][:template_base_path] = 'custom/'
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  def test_normalize_template_wrong_usage
    template_name = Datadog::Contrib::ActionView::Utils.normalize_template_name({})
    assert_equal(template_name, '{}')
  end
end
