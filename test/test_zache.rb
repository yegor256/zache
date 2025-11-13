# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'concurrent'
require 'minitest/autorun'
require 'securerandom'
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
    z = Zache.new(sync: false)
    first = z.get(:hey, lifetime: 5) { rand }
    second = z.get(:hey) { rand }
    assert_equal(first, second)
    assert_equal(1, z.size)
  end

  def test_caches_and_expires
    z = Zache.new
    first = z.get(:hey, lifetime: 0.01) { rand }
    sleep 0.1
    second = z.get(:hey) { rand }
    refute_equal(first, second)
  end

  def test_calculates_age
    z = Zache.new
    z.get(:hey) { rand }
    sleep 0.1
    assert_operator(z.mtime(:hey), :<, Time.now - 0.05)
  end

  def test_caches_in_threads
    z = Zache.new
    Threads.new(10).assert(100) do
      z.get(:hey, lifetime: 0.0001) { rand }
    end
  end

  def test_key_exists
    z = Zache.new
    z.get(:hey) { rand }
    exists_result = z.exists?(:hey)
    not_exists_result = z.exists?(:bye)
    assert(exists_result)
    refute(not_exists_result)
  end

  def test_put_and_exists
    z = Zache.new
    z.put(:hey, 'hello', lifetime: 0.1)
    sleep 0.2
    refute(z.exists?(:hey))
  end

  def test_remove_key
    z = Zache.new
    z.get(:hey) { rand }
    z.get(:wey) { rand }
    assert(z.exists?(:hey))
    assert(z.exists?(:wey))
    z.remove(:hey)
    refute(z.exists?(:hey))
    assert(z.exists?(:wey))
  end

  def test_remove_by_block
    z = Zache.new
    z.get('first') { rand }
    z.get('second') { rand }
    z.remove_by { |k| k == 'first' }
    refute(z.exists?('first'))
    assert(z.exists?('second'))
  end

  def test_remove_key_with_sync_false
    z = Zache.new(sync: false)
    z.get(:hey) { rand }
    z.get(:wey) { rand }
    assert(z.exists?(:hey))
    assert(z.exists?(:wey))
    z.remove(:hey)
    refute(z.exists?(:hey))
    assert(z.exists?(:wey))
  end

  def test_clean_with_threads
    z = Zache.new
    Threads.new(300).assert(3000) do
      z.get(:hey) { rand }
      z.get(:bye, lifetime: 0.01) { rand }
      sleep 0.1
      z.clean
    end
    assert(z.exists?(:hey))
    refute(z.exists?(:bye))
  end

  def test_clean
    z = Zache.new
    z.get(:hey) { rand }
    z.get(:bye, lifetime: 0.01) { rand }
    sleep 0.1
    z.clean
    assert(z.exists?(:hey))
    refute(z.exists?(:bye))
  end

  def test_clean_size
    z = Zache.new
    z.get(:hey, lifetime: 0.01) { rand }
    sleep 0.1
    z.clean
    assert_empty(z)
  end

  def test_clean_with_sync_false
    z = Zache.new(sync: false)
    z.get(:hey) { rand }
    z.get(:bye, lifetime: 0.01) { rand }
    sleep 0.1
    z.clean
    assert(z.exists?(:hey))
    refute(z.exists?(:bye))
  end

  def test_remove_absent_key
    z = Zache.new
    z.remove(:hey)
  end

  def test_check_and_remove
    z = Zache.new
    z.get(:hey, lifetime: -1) { rand }
    refute(z.exists?(:hey))
  end

  def test_remove_all_with_threads
    z = Zache.new
    Threads.new(10).assert(100) do |i|
      z.get(:"hey#{i}") { rand }
      assert(z.exists?(:"hey#{i}"))
      z.remove_all
    end
    10.times do |i|
      refute(z.exists?(:"hey#{i}"))
    end
  end

  def test_remove_all_with_sync
    z = Zache.new
    z.get(:hey) { rand }
    z.get(:bye) { rand }
    z.remove_all
    refute(z.exists?(:hey))
    refute(z.exists?(:bye))
  end

  def test_remove_all_without_sync
    z = Zache.new(sync: false)
    z.get(:hey) { rand }
    z.get(:bye) { rand }
    z.remove_all
    refute(z.exists?(:hey))
    refute(z.exists?(:bye))
  end

  def test_puts_something_in
    z = Zache.new(sync: false)
    z.get(:hey) { rand }
    z.put(:hey, 123)
    assert_equal(123, z.get(:hey))
  end

  def test_sync_zache_is_not_reentrant
    z = Zache.new
    assert_raises ThreadError do
      z.get(:first) { z.get(:first) { 1 } }
    end
  end

  def test_sync_zache_is_reentrant_for_different_keys
    z = Zache.new
    z.get(:first) { z.get(:second) { 1 } }
  end

  def test_calculates_only_once
    z = Zache.new
    long = Thread.start do
      z.get(:x) do
        sleep 0.5
        'first'
      end
    end
    sleep 0.1
    assert(z.locked?(:x))
    z.get(:x) { 'second' }
    refute(z.locked?(:x))
    long.kill
  end

  def test_checks_locked_status_from_inside
    z = Zache.new
    z.get(:x) do
      assert(z.locked?(:x))
      'done'
    end
    refute(z.locked?(:x))
  end

  def test_returns_dirty_result
    z = Zache.new(dirty: true)
    z.get(:x, lifetime: 0) { 1 }
    long = Thread.start do
      z.get(:x) do
        sleep 1000
        2
      end
    end
    sleep 0.1
    Timeout.timeout(1) do
      assert(z.exists?(:x))
      assert(z.expired?(:x))
      assert_equal(1, z.get(:x))
      assert_equal(1, z.get(:x) { 2 })
    end
    long.kill
  end

  def test_returns_dirty_result_when_not_locked
    z = Zache.new(dirty: true)
    z.get(:x, lifetime: 0) { 1 }
    assert(z.exists?(:x))
    assert_equal(1, z.get(:x))
    assert_equal(2, z.get(:x) { 2 })
  end

  def test_fetches_multiple_keys_in_many_threads_in_dirty_mode
    z = Zache.new(dirty: true)
    set = Concurrent::Set.new
    threads = 50
    barrier = Concurrent::CyclicBarrier.new(threads)
    Threads.new(threads).assert(threads * 2) do |i|
      barrier.wait if i < threads
      set << z.get(i, lifetime: 0.001) { i }
    end
    assert_equal(threads, set.size)
  end

  def test_fetches_multiple_keys_in_many_threads
    z = Zache.new
    set = Concurrent::Set.new
    threads = 50
    barrier = Concurrent::CyclicBarrier.new(threads)
    Threads.new(threads).assert(threads * 2) do |i|
      barrier.wait if i < threads
      set << z.get(i) { i }
    end
    assert_equal(threads, set.size)
  end

  def test_fake_class_works
    z = Zache::Fake.new
    assert_equal(1, z.get(:x) { 1 })
  end

  def test_rethrows
    z = Zache.new
    assert_raises RuntimeError do
      z.get(:hey) { raise 'intentional' }
    end
  end

  def test_returns_placeholder_in_eager_mode
    z = Zache.new
    a = z.get(:me, placeholder: 42, eager: true) do
      sleep 0.1
      43
    end
    assert_equal(42, a)
    sleep 0.2
    b = z.get(:me)
    assert_equal(43, b)
  end

  def test_returns_placeholder_and_releases_lock
    z = Zache.new
    z.get(:slow, placeholder: 42, eager: true) do
      sleep 9999
    end
    sleep 0.1
    assert_equal(555, z.get(:fast) { 555 })
  end

  def test_concurrent_reads_are_thread_safe
    z = Zache.new

    100.times { |i| z.put(i, "value_#{i}", lifetime: 10) }

    errors = Concurrent::Array.new

    Threads.new(50).assert(1000) do |i|
      key = i % 100
      perform_cache_operation(z, i, key)
    rescue StandardError => e
      errors << e
    end

    assert_empty(errors, "Thread safety errors occurred: #{errors.map(&:message).join(', ')}")
    assert_equal(100, z.size)
  end

  def test_concurrent_reads_with_writes
    z = Zache.new
    50.times { |i| z.put(i, "initial_#{i}", lifetime: 10) }
    errors = Concurrent::Array.new

    Threads.new(50).assert(300) do |i|
      key = i % 50
      perform_cache_operation(z, i, key)
    rescue StandardError => e
      errors << e
    end

    assert_empty(errors, "Race condition errors: #{errors.map(&:message).join(', ')}")
    assert_equal(50, z.size, 'Cache should still have 50 keys')
  end

  private

  def rand
    SecureRandom.uuid
  end

  def perform_cache_operation(cache, iteration, key)
    if (iteration % 5).zero?
      cache.put(key, "updated_#{iteration}", lifetime: 10)
    else
      case iteration % 7
      when 0 then cache.size
      when 1 then cache.exists?(key)
      when 2 then cache.expired?(key)
      when 3 then cache.mtime(key)
      when 4 then cache.empty?
      when 5 then cache.locked?(key)
      else cache.get(key)
      end
    end
  end
end
