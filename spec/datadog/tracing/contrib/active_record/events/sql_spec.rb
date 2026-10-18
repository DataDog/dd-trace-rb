require "spec_helper"
require "datadog/tracing/contrib/active_record/events/sql"
require "datadog/tracing/span_operation"

require "active_record"

RSpec.describe Datadog::Tracing::Contrib::ActiveRecord::Events::SQL do
  describe ".event_name" do
    it "returns the correct event name" do
      expect(described_class.event_name).to eq("sql.active_record")
    end
  end

  describe ".span_name" do
    it "returns the correct span name" do
      expect(described_class.span_name).to eq("active_record.sql")
    end
  end

  describe ".on_start" do
    let(:span) { Datadog::Tracing::SpanOperation.new("fake") }

    context "when an error occurs" do
      it "logs the error" do
        expect(Datadog.logger).to receive(:error).with(/key not found/)
        expect(Datadog::Core::Telemetry::Logger).to receive(:report).with(a_kind_of(StandardError))

        expect do
          described_class.on_start(span, double, double, {})
        end.not_to raise_error
      end
    end

    context "with a connection host" do
      subject(:on_start) { described_class.on_start(span, double, double, {sql: "SELECT 1"}) }

      let(:config) { {adapter: "mysql2", database: "orders", host: host} }

      before do
        allow(Datadog::Tracing::Contrib::ActiveRecord::Utils)
          .to receive(:connection_config).and_return(config)
      end

      context "with an Aurora writer endpoint" do
        let(:host) { "orders.cluster-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

        it "tags the cluster identity without naming an instance" do
          on_start

          expect(span.get_tag("out.host")).to eq(host)
          expect(span.get_tag("aws.rds.identifier")).to eq("orders")
          expect(span.get_tag("aws.rds.endpoint_type")).to eq("cluster")
          expect(span.get_tag("aws.region")).to eq("us-east-1")
          expect(span.get_tag("dbclusteridentifier")).to eq("orders")
          expect(span.get_tag("dbinstanceidentifier")).to be_nil
        end
      end

      context "with an RDS instance endpoint" do
        let(:host) { "orders-db.cdbfa1b2c3d4.eu-central-1.rds.amazonaws.com" }

        it "tags the instance identity" do
          on_start

          expect(span.get_tag("aws.rds.identifier")).to eq("orders-db")
          expect(span.get_tag("aws.rds.endpoint_type")).to eq("instance")
          expect(span.get_tag("aws.region")).to eq("eu-central-1")
          expect(span.get_tag("dbinstanceidentifier")).to eq("orders-db")
          expect(span.get_tag("dbclusteridentifier")).to be_nil
        end
      end

      context "with a non-RDS host" do
        let(:host) { "127.0.0.1" }

        it "adds no RDS tags" do
          on_start

          expect(span.get_tag("out.host")).to eq(host)
          expect(span.get_tag("aws.rds.identifier")).to be_nil
          expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
          expect(span.get_tag("aws.region")).to be_nil
        end
      end
    end
  end
end
