# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'concurrent'
require 'minitest/autorun'
require 'threads'
require 'timeout'
require_relative '../lib/zache'
require_relative 'test__helper'

Thread.report_on_exception = true

# Cache test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class ZacheTest < Minitest::Test
  def test_caches
    cache = Zache.new(sync: false)
    first = cache.get(:hey, lifetime: 5) { rand }
    second = cache.get(:hey) { rand }
    assert_equal(first, second)
    assert_equal(1, cache.size)
  end

  def test_caches_and_expires
    cache = Zache.new
    first = cache.get(:hey, lifetime: 0.01) { rand }
    sleep 0.1
    second = cache.get(:hey) { rand }
    refute_equal(first, second)
  end

  def test_calculates_age
    cache = Zache.new
    cache.get(:hey) { rand }
    sleep 0.1
    assert_operator(cache.mtime(:hey), :<, Time.now - 0.05)
  end

  def test_caches_in_threads
    cache = Zache.new
    Threads.new(10).assert(100) do
      cache.get(:hey, lifetime: 0.0001) { rand }
    end
  end

  def test_key_exists
    cache = Zache.new
    cache.get(:hey) { rand }
    exists_result = cache.exists?(:hey)
    not_exists_result = cache.exists?(:bye)
    assert(exists_result)
    refute(not_exists_result)
  end

  def test_put_and_exists
    cache = Zache.new
    cache.put(:hey, 'hello', lifetime: 0.1)
    sleep 0.2
    refute(cache.exists?(:hey))
  end

  def test_remove_key
    cache = Zache.new
    cache.get(:hey) { rand }
    cache.get(:wey) { rand }
    assert(cache.exists?(:hey))
    assert(cache.exists?(:wey))
    cache.remove(:hey)
    refute(cache.exists?(:hey))
    assert(cache.exists?(:wey))
  end

  def test_remove_by_block
    cache = Zache.new
    cache.get('first') { rand }
    cache.get('second') { rand }
    cache.remove_by { |k| k == 'first' }
    refute(cache.exists?('first'))
    assert(cache.exists?('second'))
  end

  def test_remove_key_with_sync_false
    cache = Zache.new(sync: false)
    cache.get(:hey) { rand }
    cache.get(:wey) { rand }
    assert(cache.exists?(:hey))
    assert(cache.exists?(:wey))
    cache.remove(:hey)
    refute(cache.exists?(:hey))
    assert(cache.exists?(:wey))
  end

  def test_clean_with_threads
    cache = Zache.new
    Threads.new(300).assert(3000) do
      cache.get(:hey) { rand }
      cache.get(:bye, lifetime: 0.01) { rand }
      sleep 0.1
      cache.clean
    end
    assert(cache.exists?(:hey))
    refute(cache.exists?(:bye))
  end

  def test_clean
    cache = Zache.new
    cache.get(:hey) { rand }
    cache.get(:bye, lifetime: 0.01) { rand }
    sleep 0.1
    cache.clean
    assert(cache.exists?(:hey))
    refute(cache.exists?(:bye))
  end

  def test_clean_size
    cache = Zache.new
    cache.get(:hey, lifetime: 0.01) { rand }
    sleep 0.1
    cache.clean
    assert_empty(cache)
  end

  def test_clean_with_sync_false
    cache = Zache.new(sync: false)
    cache.get(:hey) { rand }
    cache.get(:bye, lifetime: 0.01) { rand }
    sleep 0.1
    cache.clean
    assert(cache.exists?(:hey))
    refute(cache.exists?(:bye))
  end

  def test_remove_absent_key
    cache = Zache.new
    cache.remove(:hey)
  end

  def test_check_and_remove
    cache = Zache.new
    cache.get(:hey, lifetime: 0) { rand }
    refute(cache.exists?(:hey))
  end

  def test_remove_all_with_threads
    cache = Zache.new
    Threads.new(10).assert(100) do |i|
      cache.get(:"hey#{i}") { rand }
      assert(cache.exists?(:"hey#{i}"))
      cache.remove_all
    end
    10.times do |i|
      refute(cache.exists?(:"hey#{i}"))
    end
  end

  def test_remove_all_with_sync
    cache = Zache.new
    cache.get(:hey) { rand }
    cache.get(:bye) { rand }
    cache.remove_all
    refute(cache.exists?(:hey))
    refute(cache.exists?(:bye))
  end

  def test_remove_all_without_sync
    cache = Zache.new(sync: false)
    cache.get(:hey) { rand }
    cache.get(:bye) { rand }
    cache.remove_all
    refute(cache.exists?(:hey))
    refute(cache.exists?(:bye))
  end

  def test_puts_something_in
    cache = Zache.new(sync: false)
    cache.get(:hey) { rand }
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
    assert_predicate(cache, :locked?)
    cache.get(:x) { 'second' }
    refute_predicate(cache, :locked?)
    long.kill
  end

  def test_checks_locked_status_from_inside
    cache = Zache.new
    cache.get(:x) do
      assert_predicate(cache, :locked?)
      'done'
    end
    refute_predicate(cache, :locked?)
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
    barrier = Concurrent::CyclicBarrier.new(threads)
    Threads.new(threads).assert(threads * 2) do |i|
      barrier.wait if i < threads
      set << cache.get(i, lifetime: 0.001) { i }
    end
    assert_equal(threads, set.size)
  end

  def test_fetches_multiple_keys_in_many_threads
    cache = Zache.new
    set = Concurrent::Set.new
    threads = 50
    barrier = Concurrent::CyclicBarrier.new(threads)
    Threads.new(threads).assert(threads * 2) do |i|
      barrier.wait if i < threads
      set << cache.get(i) { i }
    end
    assert_equal(threads, set.size)
  end

  def test_fake_class_works
    cache = Zache::Fake.new
    assert_equal(1, cache.get(:x) { 1 })
  end

  def test_rethrows
    cache = Zache.new
    assert_raises RuntimeError do
      cache.get(:hey) { raise 'intentional' }
    end
  end

  def test_returns_placeholder_in_eager_mode
    cache = Zache.new
    a = cache.get(:me, placeholder: 42, eager: true) do
      sleep 0.1
      43
    end
    assert_equal(42, a)
    sleep 0.2
    b = cache.get(:me)
    assert_equal(43, b)
  end

  private

  def rand
    Random.rand
  end
end
