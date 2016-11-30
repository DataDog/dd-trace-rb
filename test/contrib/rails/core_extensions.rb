if ::Rails::VERSION::MAJOR.to_i == 3
  # Rails 3.x unsubscribes all render_template handlers during the test teardown
  # because it uses some subscribers to load @layouts @templates and @partials.
  # In our case, this disables the instrumentation after each test and because this is
  # an unwanted behavior, we simply disable this functionality. Removing both methods,
  # makes some tests assertions not possible (such as assert_template) but because we're
  # testing the tracer and not a Rails app, it's a reasonable choice.
  #
  # Reference: https://github.com/rails/rails/blob/v3.2.22.5/actionpack/lib/action_controller/test_case.rb#L45
  module ActionController
    module TemplateAssertions
      def setup_subscriptions; end

      def teardown_subscriptions; end
    end
  end
end
