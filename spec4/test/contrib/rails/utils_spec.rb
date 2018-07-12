require('helper')
require('ddtrace/contrib/rails/utils')
RSpec.describe(Utils) do
  before do
    @default_base_template = Datadog.configuration[:rails][:template_base_path]
  end
  after do
    Datadog.configuration[:rails][:template_base_path] = @default_base_template
  end
  it('normalize_template_name') do
    full_template_name = '/opt/rails/app/views/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    expect('welcome/index.html.erb').to(eq(template_name))
  end
  it('normalize_template_name_nil') do
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(nil)
    expect(template_name).to(be_nil)
  end
  it('normalize_template_name_not_a_path') do
    full_template_name = 'index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    expect('index.html.erb').to(eq(template_name))
  end
  it('normalize_template_name_without_views_prefix') do
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    expect('index.html.erb').to(eq(template_name))
  end
  it('normalize_template_name_with_custom_prefix') do
    Datadog.configuration[:rails][:template_base_path] = 'custom/'
    full_template_name = '/opt/rails/app/custom/welcome/index.html.erb'
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name(full_template_name)
    expect('welcome/index.html.erb').to(eq(template_name))
  end
  it('normalize_template_wrong_usage') do
    template_name = Datadog::Contrib::Rails::Utils.normalize_template_name({})
    expect('{}').to(eq(template_name))
  end
end
