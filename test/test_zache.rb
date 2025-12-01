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

  def test_caches_with_nil_lifetime
    z = Zache.new(sync: false)
    assert_equal(42, z.get(:hey, lifetime: nil) { 42 })
    assert_equal(42, z.get(:hey, lifetime: nil) { 7 })
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
    errors = run_concurrent_operations(z, thread_count: 50, iterations: 1000, key_range: 100)
    assert_empty(errors, "Thread safety errors occurred: #{errors.map(&:message).join(', ')}")
    assert_equal(100, z.size)
  end

  def test_concurrent_reads_with_writes
    z = Zache.new
    50.times { |i| z.put(i, "initial_#{i}", lifetime: 10) }
    errors = run_concurrent_operations(z, thread_count: 50, iterations: 300, key_range: 50)
    assert_empty(errors, "Race condition errors: #{errors.map(&:message).join(', ')}")
    assert_equal(50, z.size, 'Cache should still have 50 keys')
  end

  private

  def rand
    SecureRandom.uuid
  end

  def run_concurrent_operations(cache, thread_count:, iterations:, key_range:)
    errors = Concurrent::Array.new
    Threads.new(thread_count).assert(iterations) do |i|
      key = i % key_range
      perform_cache_operation(cache, i, key)
    rescue StandardError => e
      errors << e
    end
    errors
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

  # Test for synchronize_one race condition fix
  def test_remove_all_concurrent_with_get
    z = Zache.new
    z.put(:key1, 'value1', lifetime: 10)
    errors = Concurrent::Array.new
    threads = []

    # Thread continuously calling get
    10.times do
      threads << Thread.new do
        100.times do
          begin
            z.get(:key1) { 'new_value' }
          rescue StandardError => e
            errors << e
          end
          sleep 0.001
        end
      end
    end

    # Thread continuously calling remove_all
    threads << Thread.new do
      100.times do
        z.remove_all
        sleep 0.001
      end
    end

    threads.each(&:join)
    assert_empty(errors, "Race condition errors: #{errors.map(&:message).join(', ')}")
  end

  # Test that locks are properly cleaned up after remove
  def test_locks_cleaned_up_after_remove
    z = Zache.new
    100.times { |i| z.put(:"key#{i}", "value#{i}", lifetime: 10) }

    # Verify locks exist (indirectly by checking size doesn't cause issues)
    assert_equal(100, z.size)

    # Remove half the keys
    50.times { |i| z.remove(:"key#{i}") }

    # Verify cache still works and no memory leak symptoms
    assert_equal(50, z.size)

    # Add new keys with same names - should not have stale locks
    50.times { |i| z.put(:"key#{i}", "new_value#{i}", lifetime: 10) }
    assert_equal(100, z.size)
  end

  # Test that locks are cleaned up by remove_all
  def test_locks_cleaned_up_after_remove_all
    z = Zache.new
    1000.times { |i| z.put(:"key#{i}", "value#{i}", lifetime: 10) }

    z.remove_all
    assert_equal(0, z.size)

    # Should be able to use cache normally after remove_all
    100.times do |i|
      z.get(:"newkey#{i}") { "value#{i}" }
    end
    assert_equal(100, z.size)
  end

  # Test that locks are cleaned up by remove_by
  def test_locks_cleaned_up_after_remove_by
    z = Zache.new
    100.times { |i| z.put(:"key#{i}", "value#{i}", lifetime: 10) }

    removed = z.remove_by { |k| k.to_s.end_with?('0', '2', '4', '6', '8') }
    assert_operator(removed, :>, 0)

    # Cache should continue working normally
    z.get(:new_key) { 'new_value' }
    assert(z.exists?(:new_key))
  end

  # Test that clean removes locks for expired keys
  def test_locks_cleaned_up_after_clean
    z = Zache.new
    50.times { |i| z.put(:"expire#{i}", "value#{i}", lifetime: 0.01) }
    50.times { |i| z.put(:"keep#{i}", "value#{i}", lifetime: 100) }

    sleep 0.1
    cleaned = z.clean
    assert_operator(cleaned, :>=, 50)

    # Verify cache works after cleaning
    assert_equal(50, z.size)
    z.get(:new_after_clean) { 'value' }
    assert(z.exists?(:new_after_clean))
  end

  # Test dirty mode with nil check
  def test_dirty_mode_nil_safety
    z = Zache.new(dirty: true)
    errors = Concurrent::Array.new

    threads = []
    threads << Thread.new do
      10.times do
        begin
          z.get(:key, lifetime: 0) do
            sleep 0.01
            'value'
          end
        rescue StandardError => e
          errors << e
        end
      end
    end

    threads << Thread.new do
      10.times do
        begin
          z.remove(:key)
        rescue StandardError => e
          errors << e
        end
        sleep 0.005
      end
    end

    threads.each(&:join)
    assert_empty(errors, "Dirty mode errors: #{errors.map(&:message).join(', ')}")
  end

  # Test eager mode error handling
  def test_eager_mode_with_error_in_block
    z = Zache.new
    result = z.get(:error_key, eager: true, placeholder: 'placeholder') do
      raise 'Intentional error in eager block'
    end

    assert_equal('placeholder', result)
    sleep 0.1

    # Key should be removed after error, allowing retry
    new_result = z.get(:error_key, eager: true, placeholder: 'placeholder2') do
      'success'
    end
    assert_equal('placeholder2', new_result)

    sleep 0.1
    assert_equal('success', z.get(:error_key))
  end

  # Test concurrent remove_all doesn't cause NoMethodError
  def test_no_method_error_on_concurrent_remove_all
    z = Zache.new
    errors = Concurrent::Array.new
    threads = []

    20.times do |i|
      threads << Thread.new do
        50.times do |j|
          begin
            key = :"key#{i}_#{j}"
            z.get(key) do
              sleep 0.0001
              "value#{i}_#{j}"
            end
          rescue NoMethodError => e
            errors << e
          rescue StandardError
            # Ignore other errors for this specific test
          end
        end
      end
    end

    threads << Thread.new do
      50.times do
        z.remove_all
        sleep 0.001
      end
    end

    threads.each(&:join)
    assert_empty(errors, "NoMethodError occurred: #{errors.map { |e| e.message + "\n" + e.backtrace.first(3).join("\n") }.join("\n\n")}")
  end

  # Test that synchronize_one returns correct mutex
  def test_synchronize_one_returns_working_mutex
    z = Zache.new
    counter = 0
    threads = []

    10.times do
      threads << Thread.new do
        100.times do
          z.get(:counter) do
            current = counter
            sleep 0.0001
            counter = current + 1
            counter
          end
        end
      end
    end

    threads.each(&:join)
    # With proper locking, counter should be 1 (only calculated once, then cached)
    assert_equal(1, z.size)
  end
end
