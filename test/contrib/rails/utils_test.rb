require 'helper'

require 'ddtrace/contrib/rails/utils'

class UtilsTest < Minitest::Test
  def setup
    @default_base_template = ::Rails.configuration.datadog_trace.fetch(:template_base_path)
  end

  def teardown
    ::Rails.configuration.datadog_trace[:template_base_path] = @default_base_template
  end

  def test_normalize_template_name
    full_template_name = '/opt/rails/app/views/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  def test_normalize_template_name_nil
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(nil)
    assert_equal(template_name, nil)
  end

  def test_normalize_template_name_not_a_path
    full_template_name = 'index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  def test_normalize_template_name_without_views_prefix
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  def test_normalize_template_name_with_custom_prefix
    ::Rails.configuration.datadog_trace[:template_base_path] = 'custom/'
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  def test_normalize_template_wrong_usage
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name({})
    assert_equal(template_name, '{}')
  end
end
