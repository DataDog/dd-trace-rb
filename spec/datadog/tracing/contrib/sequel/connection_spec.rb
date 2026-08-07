require "datadog/tracing/contrib/support/spec_helper"
require "sequel"
require "datadog"
require "datadog/tracing/contrib/sequel/integration"
require "datadog/tracing/contrib/sequel/connection"

RSpec.describe Datadog::Tracing::Contrib::Sequel::Connection do
  before do
    skip("Sequel connection specs require the native pg adapter on CRuby.") if PlatformHelpers.jruby?
    skip("Sequel not compatible.") unless Datadog::Tracing::Contrib::Sequel::Integration.compatible?

    Datadog.configure do |c|
      c.tracing.instrument :sequel
    end
  end

  around do |example|
    Datadog.registry[:sequel].reset_configuration!
    Sequel::DATABASES.each(&:disconnect)
    example.run
    Sequel::DATABASES.each(&:disconnect)
    Datadog.registry[:sequel].reset_configuration!
  end

  subject(:logged_result) do
    sequel.synchronize do |conn|
      sequel.log_connection_yield("SELECT 1", conn) do
        conn.async_exec("SELECT 1")
      end
    end
  end

  let(:sequel) do
    Sequel.connect(connection_string).tap do |db|
      Datadog.configure_onto(db)
    end
  end

  let(:connection_string) do
    user = ENV.fetch("TEST_POSTGRES_USER", "postgres")
    password = ENV.fetch("TEST_POSTGRES_PASSWORD", "postgres")
    host = ENV.fetch("TEST_POSTGRES_HOST", "127.0.0.1")
    port = ENV.fetch("TEST_POSTGRES_PORT", "5432")
    db = ENV.fetch("TEST_POSTGRES_DB", "postgres")

    # libpq tries these in order. The first endpoint is intentionally closed;
    # the active PG connection then reports the selected second endpoint through
    # conn.host/conn.port while db.opts keeps the original multi-host values.
    "postgres:///?host=#{host},#{host}&port=1,#{port}&user=#{user}&password=#{password}&dbname=#{db}&connect_timeout=2"
  end

  context "when the active span is a Sequel query span" do
    it "tags the active span with selected connection metadata" do
      tracer.trace(Datadog::Tracing::Contrib::Sequel::Ext::SPAN_QUERY) do
        logged_result
      end

      span = spans.first
      expect(span.name).to eq("sequel.query")
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(ENV.fetch("TEST_POSTGRES_HOST", "127.0.0.1"))
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(ENV.fetch("TEST_POSTGRES_HOST", "127.0.0.1"))
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(ENV.fetch("TEST_POSTGRES_PORT", "5432"))
    end
  end

  context "when there is no active span" do
    it "does not create or tag a span" do
      logged_result

      expect(spans).to be_empty
    end
  end

  context "when the active span is not a Sequel query span" do
    it "does not tag the active span with connection metadata" do
      tracer.trace("rack.request") do
        logged_result
      end

      span = spans.first
      expect(span.name).to eq("rack.request")
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to be_nil
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to be_nil
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to be_nil
    end
  end
end
