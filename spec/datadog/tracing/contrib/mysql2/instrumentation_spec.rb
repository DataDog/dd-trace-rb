require "datadog/tracing/contrib/support/spec_helper"

require "datadog"
require "datadog/tracing/contrib/mysql2/instrumentation"

RSpec.describe Datadog::Tracing::Contrib::Mysql2::Instrumentation do
  let(:client_class) do
    Class.new do
      attr_reader :query_options

      def initialize(query_options)
        @query_options = query_options
      end

      def query(sql, options = {})
        [sql, options]
      end

      include Datadog::Tracing::Contrib::Mysql2::Instrumentation
    end
  end

  let(:client) { client_class.new(host: host, port: 3306, database: "orders") }

  before { client.query("SELECT 1") }

  context "with an RDS instance endpoint" do
    let(:host) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

    it "tags the RDS identity alongside the existing host tags" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to eq("orders-db")
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("instance")
      expect(span.get_tag("aws.region")).to eq("us-east-1")
      expect(span.get_tag("dbinstanceidentifier")).to eq("orders-db")
      expect(span.get_tag("dbclusteridentifier")).to be_nil
    end
  end

  context "with an Aurora reader endpoint" do
    let(:host) { "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com" }

    it "tags the cluster identity without naming an instance" do
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("cluster-ro")
      expect(span.get_tag("dbclusteridentifier")).to eq("orders")
      expect(span.get_tag("dbinstanceidentifier")).to be_nil
    end
  end

  context "with a non-RDS host" do
    let(:host) { "127.0.0.1" }

    it "leaves the span unchanged" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to be_nil
      expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
      expect(span.get_tag("aws.region")).to be_nil
    end
  end

  context "with no host" do
    let(:host) { nil }

    it "leaves the span unchanged" do
      expect(span.get_tag("aws.rds.identifier")).to be_nil
      expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
      expect(span.get_tag("aws.region")).to be_nil
    end
  end
end
