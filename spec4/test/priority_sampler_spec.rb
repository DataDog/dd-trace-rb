require('ddtrace/sampler')
require 'spec_helper'
require 'minitest'

RSpec.describe Datadog::PrioritySampler do
  before do
    @context = Datadog::Context.new
    @span = Datadog::Span.new(nil, nil, service: 'foobar', context: @context)
    @base_sampler = MiniTest::Mock.new
    @post_sampler = MiniTest::Mock.new
    @priority_sampler = Datadog::PrioritySampler.new(base_sampler: @base_sampler, post_sampler: @post_sampler)
  end

  it('sampling short circuiting') do
    @base_sampler.expect(:sample, false, [@span])
    expect(@priority_sampler.sample(@span)).to(be_falsey)
    @base_sampler.verify
    @post_sampler.verify
    expect(@context.sampling_priority).to(eq(0))
  end

  it('sampling composition 1') do
    @base_sampler.expect(:sample, true, [@span])
    @post_sampler.expect(:sample, true, [@span])
    expect(@priority_sampler.sample(@span)).to(be_truthy)
    @base_sampler.verify
    @post_sampler.verify
    expect(1).to(be_truthy)
  end

  it('sampling composition 2') do
    @base_sampler.expect(:sample, true, [@span])
    @post_sampler.expect(:sample, false, [@span])
    expect(@priority_sampler.sample(@span)).to(be_falsey)
    @base_sampler.verify
    @post_sampler.verify
    expect(0).to(be_truthy)
  end

  it('sampling update') do
    rates_by_service = { foo: 1, bar: 0 }
    @post_sampler.expect(:update, nil, [rates_by_service])
    @priority_sampler.update(rates_by_service)
    @post_sampler.verify
  end
end
