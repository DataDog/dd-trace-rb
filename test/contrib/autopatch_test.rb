require 'minitest'
require 'minitest/autorun'
require 'ddtrace'
require 'ddtrace/contrib/autopatch'
require 'ddtrace/contrib/elasticsearch/patch'
require 'ddtrace/contrib/redis/patch'
require 'elasticsearch/transport'
require 'redis'

class AutopatchTest < Minitest::Test
  def test_autopatch_modules
    assert_equal(%w(elasticsearch redis), Datadog::Contrib::Autopatch.autopatch_modules)
  end

  def test_patch_modules
    # because of this test, this should be a separate rake task,
    # else the module could have been already imported in some other test
    assert_equal(false, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patch.patched?)

    Datadog::Contrib::Autopatch.patch_modules(['redis'])
    assert_equal(true, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patch.patched?)

    # now do it again to check it's idempotent
    Datadog::Contrib::Autopatch.patch_modules(['redis'])
    assert_equal(true, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patch.patched?)

    Datadog::Contrib::Autopatch.patch_modules(%w(elasticsearch redis))
    assert_equal(true, Datadog::Contrib::Redis::Patch.patched?)
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patch.patched?)
  end
end
