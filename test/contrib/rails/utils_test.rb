require 'helper'

require 'ddtrace/contrib/rails/utils'

class UtilsTest < ActiveSupport::TestCase
  setup do
    @default_base_template = Datadog.configuration[:rails][:template_base_path]
  end

  teardown do
    Datadog.configuration[:rails][:template_base_path] = @default_base_template
  end

  test 'normalize_template_name' do
    full_template_name = '/opt/rails/app/views/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  test 'normalize_template_name_nil' do
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(nil)
    assert_nil(template_name)
  end

  test 'normalize_template_name_not_a_path' do
    full_template_name = 'index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  test 'normalize_template_name_without_views_prefix' do
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  test 'normalize_template_name_with_custom_prefix' do
    Datadog.configuration[:rails][:template_base_path] = 'custom/'
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'welcome/index.html.erb')
  end

  test 'normalize_template_wrong_usage' do
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name({})
    assert_equal(template_name, '{}')
  end

  test 'normalize adapter name for a not defined vendor' do
    vendor = Datadog::Contrib::Rails::Utils.normalize_vendor(nil)
    assert_equal(vendor, 'defaultdb')
  end

  test 'normalize adapter name for sqlite3' do
    vendor = Datadog::Contrib::Rails::Utils.normalize_vendor('sqlite3')
    assert_equal(vendor, 'sqlite')
  end

  test 'normalize adapter name for postgresql' do
    vendor = Datadog::Contrib::Rails::Utils.normalize_vendor('postgresql')
    assert_equal(vendor, 'postgres')
  end

  test 'normalize adapter name for an unknown vendor' do
    vendor = Datadog::Contrib::Rails::Utils.normalize_vendor('customdb')
    assert_equal(vendor, 'customdb')
  end
end
