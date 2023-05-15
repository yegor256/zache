# frozen_string_literal: true

# (The MIT License)
#
# Copyright (c) 2018-2023 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'threads'
require 'timeout'
require 'concurrent'
require_relative '../lib/zache'

Thread.report_on_exception = true

# Cache test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2023 Yegor Bugayenko
# License:: MIT
class ZacheTest < Minitest::Test
  def test_caches
    cache = Zache.new(sync: false)
    first = cache.get(:hey, lifetime: 5) { Random.rand }
    second = cache.get(:hey) { Random.rand }
    assert(first == second)
    assert_equal(1, cache.size)
  end

  def test_caches_and_expires
    cache = Zache.new
    first = cache.get(:hey, lifetime: 0.01) { Random.rand }
    sleep 0.1
    second = cache.get(:hey) { Random.rand }
    assert(first != second)
  end

  def test_calculates_age
    cache = Zache.new
    cache.get(:hey) { Random.rand }
    sleep 0.1
    assert(cache.mtime(:hey) < Time.now - 0.05)
  end

  def test_caches_in_threads
    cache = Zache.new
    Threads.new(10).assert(100) do
      cache.get(:hey, lifetime: 0.0001) { Random.rand }
    end
  end

  def test_key_exists
    cache = Zache.new
    cache.get(:hey) { Random.rand }
    exists_result = cache.exists?(:hey)
    not_exists_result = cache.exists?(:bye)
    assert(exists_result == true)
    assert(not_exists_result == false)
  end

  def test_put_and_exists
    cache = Zache.new
    cache.put(:hey, 'hello', lifetime: 0.1)
    sleep 0.2
    assert(!cache.exists?(:hey))
  end

  def test_remove_key
    cache = Zache.new
    cache.get(:hey) { Random.rand }
    cache.get(:wey) { Random.rand }
    assert(cache.exists?(:hey) == true)
    assert(cache.exists?(:wey) == true)
    cache.remove(:hey)
    assert(cache.exists?(:hey) == false)
    assert(cache.exists?(:wey) == true)
  end

  def test_remove_by_block
    cache = Zache.new
    cache.get('first') { Random.rand }
    cache.get('second') { Random.rand }
    cache.remove_by { |k| k == 'first' }
    assert(cache.exists?('first') == false)
    assert(cache.exists?('second') == true)
  end

  def test_remove_key_with_sync_false
    cache = Zache.new(sync: false)
    cache.get(:hey) { Random.rand }
    cache.get(:wey) { Random.rand }
    assert(cache.exists?(:hey) == true)
    assert(cache.exists?(:wey) == true)
    cache.remove(:hey)
    assert(cache.exists?(:hey) == false)
    assert(cache.exists?(:wey) == true)
  end

  def test_clean_with_threads
    cache = Zache.new
    Threads.new(300).assert(3000) do
      cache.get(:hey) { Random.rand }
      cache.get(:bye, lifetime: 0.01) { Random.rand }
      sleep 0.1
      cache.clean
    end
    assert(cache.exists?(:hey) == true)
    assert(cache.exists?(:bye) == false)
  end

  def test_clean
    cache = Zache.new
    cache.get(:hey) { Random.rand }
    cache.get(:bye, lifetime: 0.01) { Random.rand }
    sleep 0.1
    cache.clean
    assert(cache.exists?(:hey) == true)
    assert(cache.exists?(:bye) == false)
  end

  def test_clean_with_sync_false
    cache = Zache.new(sync: false)
    cache.get(:hey) { Random.rand }
    cache.get(:bye, lifetime: 0.01) { Random.rand }
    sleep 0.1
    cache.clean
    assert(cache.exists?(:hey) == true)
    assert(cache.exists?(:bye) == false)
  end

  def test_remove_absent_key
    cache = Zache.new
    cache.remove(:hey)
  end

  def test_check_and_remove
    cache = Zache.new
    cache.get(:hey, lifetime: 0) { Random.rand }
    assert(!cache.exists?(:hey))
  end

  def test_remove_all_with_threads
    cache = Zache.new
    Threads.new(10).assert(100) do |i|
      cache.get("hey#{i}".to_sym) { Random.rand }
      assert(cache.exists?("hey#{i}".to_sym) == true)
      cache.remove_all
    end
    10.times do |i|
      assert(cache.exists?("hey#{i}".to_sym) == false)
    end
  end

  def test_remove_all_with_sync
    cache = Zache.new
    cache.get(:hey) { Random.rand }
    cache.get(:bye) { Random.rand }
    cache.remove_all
    assert(cache.exists?(:hey) == false)
    assert(cache.exists?(:bye) == false)
  end

  def test_remove_all_without_sync
    cache = Zache.new(sync: false)
    cache.get(:hey) { Random.rand }
    cache.get(:bye) { Random.rand }
    cache.remove_all
    assert(cache.exists?(:hey) == false)
    assert(cache.exists?(:bye) == false)
  end

  def test_puts_something_in
    cache = Zache.new(sync: false)
    cache.get(:hey) { Random.rand }
    cache.put(:hey, 123)
    assert_equal(123, cache.get(:hey))
  end

  def test_sync_zache_is_not_reentrant
    cache = Zache.new
    assert_raises ThreadError do
      cache.get(:first) { cache.get(:second) { 1 } }
    end
  end

  def test_calculates_only_once
    cache = Zache.new
    long = Thread.start do
      cache.get(:x) do
        sleep 0.5
        'first'
      end
    end
    sleep 0.1
    assert(cache.locked?)
    cache.get(:x) { 'second' }
    assert(!cache.locked?)
    long.kill
  end

  def test_checks_locked_status_from_inside
    cache = Zache.new
    cache.get(:x) do
      assert(cache.locked?)
      'done'
    end
    assert(!cache.locked?)
  end

  def test_returns_dirty_result
    cache = Zache.new(dirty: true)
    cache.get(:x, lifetime: 0) { 1 }
    long = Thread.start do
      cache.get(:x) do
        sleep 1000
        2
      end
    end
    sleep 0.1
    Timeout.timeout(1) do
      assert(cache.exists?(:x))
      assert(cache.expired?(:x))
      assert_equal(1, cache.get(:x))
      assert_equal(1, cache.get(:x) { 2 })
    end
    long.kill
  end

  def test_returns_dirty_result_when_not_locked
    cache = Zache.new(dirty: true)
    cache.get(:x, lifetime: 0) { 1 }
    assert(cache.exists?(:x))
    assert_equal(1, cache.get(:x))
    assert_equal(2, cache.get(:x) { 2 })
  end

  def test_fetches_multiple_keys_in_many_threads_in_dirty_mode
    cache = Zache.new(dirty: true)
    set = Concurrent::Set.new
    threads = 50
    Threads.new(threads).assert(threads * 2) do |i|
      set << cache.get(i, lifetime: 0.001) { i }
    end
    assert_equal(threads, set.size)
  end

  def test_fetches_multiple_keys_in_many_threads
    cache = Zache.new
    set = Concurrent::Set.new
    threads = 50
    Threads.new(threads).assert(threads * 2) do |i|
      set << cache.get(i) { i }
    end
    assert_equal(threads, set.size)
  end

  def test_fake_class_works
    cache = Zache::Fake.new
    assert_equal(1, cache.get(:x) { 1 })
  end
end
