require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require_relative 'app'

RSpec.describe 'ActiveRecord async instrumentation' do
  let(:configuration_options) { {} }

  before do
    # Prevent extra spans during tests
    Article.count
    clear_traces!

    # Reset options (that might linger from other tests)
    Datadog.configuration.tracing[:active_record].reset!

    Datadog.configure do |c|
      c.tracing.instrument :active_record, configuration_options
      c.tracing.instrument :concurrent_ruby
      c.tracing.instrument :mysql2
    end

    raise_on_rails_deprecation!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:active_record].reset_configuration!
    example.run
    Datadog.registry[:active_record].reset_configuration!
  end

  context 'with adapter supporting background execution' do
    before { skip('Rails < 7 does not support async queries') if ActiveRecord::VERSION::MAJOR < 7 }

    subject { nil } # Delay query to inside the trace block

    it 'parents the database span to the calling context' do
      root_span = Datadog::Tracing.trace('root-span') do |span|
        relation = Article.limit(1).load_async # load_async was the only async method in Rails 7.0

        # Confirm async execution (there's no public API to confirm it).
        expect(relation.instance_variable_get(:@future_result)).to_not be_nil

        # Ensure we didn't break the query
        expect(relation.to_a).to be_a(Array)

        span
      end

      # Remove boilerplate DB spans, like `SET` statements.
      select = spans.select { |s| s.resource =~ /select.*articles/i }

      # Ensure all DB spans are either children of the root span or nested spans.
      expect(select).to all(not_be(be_root_span))

      ar_spans = select.select { |s| s.get_tag('component') == 'active_record' }

      expect(ar_spans).to have(1).item
      expect(ar_spans[0].parent_id).to eq(root_span.id)
    end
  end
end
