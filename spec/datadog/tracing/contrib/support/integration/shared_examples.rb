# frozen_string_literal: true

RSpec.shared_examples 'a trace with APM disablement tags' do |params = {}|
  let(:tag_apm_enabled) { params[:tag_apm_enabled] || 0 }
  let(:tag_other_propagation) { params[:tag_other_propagation] || :any }
  # We use a lambda as we may change the comparison type
  let(:tag_sampling_priority_condition) { params[:tag_sampling_priority_condition] || ->(x) { x == 0 } }
  let(:tag_trace_id) { params[:tag_trace_id] || headers_trace_id.to_i }

  it do
    expect(span.send(:metrics)['_dd.apm.enabled']).to eq(tag_apm_enabled)
    expect(span.send(:metrics)['_sampling_priority_v1']).to(satisfy { |x| tag_sampling_priority_condition.call(x) })

    expect(span.send(:meta)['_dd.p.other']).to eq(tag_other_propagation) unless tag_other_propagation == :any

    expect(span.send(:trace_id)).to eq(tag_trace_id)
    expect(traces.last.send(:spans)[0].send(:trace_id)).to eq(tag_trace_id)
  end
end

RSpec.shared_examples 'a request sent with propagated headers' do |params = {}|
  let(:res_origin) { params[:res_origin] }
  let(:res_parent_id_not_equal) { params[:res_parent_id_not_equal] }
  let(:res_tags) { params[:res_tags] }
  let(:res_sampling_priority_condition) { params[:res_sampling_priority_condition] || lambda(&:nil?) }
  let(:res_trace_id) { params[:res_trace_id] }

  let(:res_headers) { JSON.parse(response.body) }

  it do
    expect(res_headers['X-Datadog-Origin']).to eq(res_origin)
    expect(res_headers['X-Datadog-Parent']).to_not eq(res_parent_id_not_equal) if res_parent_id_not_equal
    expect(res_headers['X-Datadog-Sampling-Priority']).to(satisfy { |x| res_sampling_priority_condition.call(x) })
    expect(res_headers['X-Datadog-Trace-Id']).to eq(res_trace_id)
    expect(res_headers['X-Datadog-Tags'].split(',')).to include(*res_tags) if res_tags
  end
end

RSpec.shared_examples 'a request sent without propagated headers' do
  it_behaves_like 'a request sent with propagated headers', {}
end
