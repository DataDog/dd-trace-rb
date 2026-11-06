require "datadog/tracing/contrib/support/spec_helper"

require "datadog"
require "datadog/tracing/contrib/trilogy/instrumentation"

RSpec.describe Datadog::Tracing::Contrib::Trilogy::Instrumentation do
  let(:client_class) do
    Class.new do
      attr_reader :connection_options

      def initialize(connection_options)
        @connection_options = connection_options
      end

      def query(sql)
        sql
      end

      include Datadog::Tracing::Contrib::Trilogy::Instrumentation
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

  context "with an Aurora writer endpoint" do
    let(:host) { "orders.cluster-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

    it "tags the cluster identity without naming an instance" do
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("cluster")
      expect(span.get_tag("dbclusteridentifier")).to eq("orders")
      expect(span.get_tag("dbinstanceidentifier")).to be_nil
    end
  end

  context "with a non-RDS host" do
    let(:host) { "mysql.internal.example.com" }

    it "leaves the span unchanged" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to be_nil
      expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
      expect(span.get_tag("aws.region")).to be_nil
    end
  end
end
