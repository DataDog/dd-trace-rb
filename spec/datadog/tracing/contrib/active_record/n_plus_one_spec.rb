require 'datadog/tracing/contrib/support/spec_helper'

require 'ddtrace'
require 'active_record'

require_relative 'app'

require 'bullet'

RSpec.describe "N+1 detection reporting" do
  before do
    Datadog.configure do |c|
      c.tracing.instrument :active_record, configuration_options
    end

    Bullet.enable = true
  end

  after do
    Bullet.enable = false
    Datadog.registry[:active_record].reset_configuration!
  end

  context 'with report_bullet: true' do
    let(:configuration_options) { { report_bullet: true } } # TODO: better naming for this option?

    def with_traced_bullet
      def named_method # A named method that we can assert as part of the stack trace
        yield
      end

      named_method do
        tracer.trace('test') do
          Bullet.profile do
            yield
          end
        end
      rescue
      end
    end

    context 'with a n+1 query' do
      it 'captures bullet error in the active span' do
        with_traced_bullet do
          Article.all.each { |article| article.user }
        end

        expect(root_span).to have_error
        expect(root_span).to have_error_type(Bullet::Notification::UnoptimizedQueryError.to_s)
        expect(root_span).to have_error_message(include("USE eager loading detected"))
        expect(root_span).to have_error_message(include("Article => [:user]"))
        expect(root_span).to have_error_message(include("Add to your query: .includes([:user])"))
        expect(root_span).to have_error_stack(/in.*named_method/)
      end

      context 'with application error' do
        it 'does not override application error with bullet error' do
          with_traced_bullet do
            Article.all.each { |article| article.user }
            raise ArgumentError, 'app error'
          end

          expect(root_span).to have_error_type(ArgumentError.to_s)
          expect(root_span).to have_error_message('app error')
        end
      end
    end

    context 'with an unused eager loading' do
      it 'captures bullet error in the active span' do
        with_traced_bullet do
          Article.preload(:user).load
        end

        expect(root_span).to have_error
        expect(root_span).to have_error_type(Bullet::Notification::UnoptimizedQueryError.to_s)
        expect(root_span).to have_error_message(include("AVOID eager loading detected"))
        expect(root_span).to have_error_message(include("Article => [:user]"))
        expect(root_span).to have_error_message(include("Remove from your query: .includes([:user])"))
        expect(root_span).to have_error_stack(/in.*named_method/)
      end
    end

    context 'with a counter cache needed' do
      it 'captures bullet error in the active span' do
        with_traced_bullet do
          User.all.each do |user|
            user.articles.reset.size
          end
        end

        Class.new { extend Bullet::StackTraceFilter }.caller_in_project

        expect(root_span).to have_error
        expect(root_span).to have_error_type(Bullet::Notification::UnoptimizedQueryError.to_s)
        expect(root_span).to have_error_message(include("Need Counter Cache"))
        expect(root_span).to have_error_message(include("User => [:articles]"))
        expect(root_span).to have_error_stack(/in.*named_method/)
      end
    end
  end

  # DEV: [Prosopite](https://rubygems.org/gems/prosopite) also detects N+1, but is less popular then Bullet.
  # DEV: This is likely a `community/help-wanted` feature request.
  # context 'with report_prosopite: true' do
  # end
end