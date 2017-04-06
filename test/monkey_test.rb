require 'minitest'
require 'minitest/autorun'
require 'ddtrace'
require 'active_record'
require 'elasticsearch/transport'
require 'redis'

class MonkeyTest < Minitest::Test
  def test_autopatch_modules
    assert_equal({ elasticsearch: true, http: true, redis: true, active_record: false }, Datadog::Monkey.autopatch_modules)
  end

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/LineLength
  def test_patch_module
    # because of this test, this should be a separate rake task,
    # else the module could have been already imported in some other test
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ elasticsearch: false, http: false, redis: false, active_record: false }, Datadog::Monkey.get_patched_modules())

    Datadog::Monkey.patch_module(:redis)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ elasticsearch: false, http: false, redis: true, active_record: false }, Datadog::Monkey.get_patched_modules())

    # now do it again to check it's idempotent
    Datadog::Monkey.patch_module(:redis)
    assert_equal(false, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ elasticsearch: false, http: false, redis: true, active_record: false }, Datadog::Monkey.get_patched_modules())

    Datadog::Monkey.patch(elasticsearch: true, redis: true)
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ elasticsearch: true, http: false, redis: true, active_record: false }, Datadog::Monkey.get_patched_modules())

    # verify that active_record is not auto patched by default
    Datadog::Monkey.patch_all()
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(false, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ elasticsearch: true, http: true, redis: true, active_record: false }, Datadog::Monkey.get_patched_modules())

    Datadog::Monkey.patch_module(:active_record)
    assert_equal(true, Datadog::Contrib::Elasticsearch::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::HTTP::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::Redis::Patcher.patched?)
    assert_equal(true, Datadog::Contrib::ActiveRecord::Patcher.patched?)
    assert_equal({ elasticsearch: true, http: true, redis: true, active_record: true }, Datadog::Monkey.get_patched_modules())
  end
end
