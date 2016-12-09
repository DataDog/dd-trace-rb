require 'minitest'
require 'minitest/autorun'
require 'ddtrace'
require 'ddtrace/monkey'
require 'ddtrace/contrib/elasticsearch/patch'
require 'ddtrace/contrib/redis/patch'
require 'elasticsearch/transport'
require 'redis'

class MonkeyTest < Minitest::Test
  def test_autopatch_modules
    assert_equal(%w(elasticsearch redis), Datadog::Monkey.autopatch_modules)
  end

  def test_patch_module
    # because of this test, this should be a separate rake task,
    # else the module could have been already imported in some other test
    assert_equal(false, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patch.patched?)

    Datadog::Monkey.patch_module('redis')
    assert_equal(true, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patch.patched?)

    # now do it again to check it's idempotent
    Datadog::Monkey.patch_module('redis')
    assert_equal(true, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patch.patched?)

    Datadog::Monkey.patch(%w(elasticsearch redis))
    assert_equal(true, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patch.patched?)
  end
end
