require 'helper'

require 'ddtrace/contrib/rails/utils'

class UtilsTest < Minitest::Test
  def test_normalize_template_name
    full_template_name = '/opt/rails/app/views/welcome/index.html.erb'
    template_name = Datadog::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end

  def test_normalize_template_name_nil
    template_name = Datadog::Utils.normalize_template_name(nil)
    assert_equal(template_name, nil)
  end

  def test_normalize_template_name_not_a_path
    full_template_name = 'index.html.erb'
    template_name = Datadog::Utils.normalize_template_name(full_template_name)
    assert_equal(template_name, 'index.html.erb')
  end
end
