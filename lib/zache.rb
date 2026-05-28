# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2026 Yegor Bugayenko
# SPDX-License-Identifier: MIT

# It is a very simple thread-safe in-memory cache with an ability to expire
# keys automatically, when their lifetime is over. Use it like this:
#
#  require 'zache'
#  zache = Zache.new
#  # Expires in 5 minutes
#  v = zache.get(:count, lifetime: 5 * 60) { expensive() }
#
# For more information read
# {README}[https://github.com/yegor256/zache/blob/master/README.md] file.
#
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2026 Yegor Bugayenko
# License:: MIT
class Zache
  # Fake implementation that doesn't cache anything, but behaves like it
  # does. It implements all methods of the original class, but doesn't do
  # any caching. This is very useful for testing.
  class Fake
    # Returns a fixed size of 1.
    # @return [Integer] Always returns 1
    def size
      1
    end

    # Always returns the result of the block, never caches.
    # @yield Block that provides the value
    # @return [Object] The result of the block
    def get(*)
      yield
    end

    # Always returns true regardless of the key.
    # @return [Boolean] Always returns true
    def exists?(*)
      true
    end

    # Always returns false.
    # @param [Object] _key Ignored
    # @return [Boolean] Always returns false
    def locked?(_key)
      false
    end

    # No-op method that ignores the input.
    # @return [nil] Always returns nil
    def put(*); end

    # No-op method that ignores the key.
    # @param [Object] _key Ignored
    # @return [nil] Always returns nil
    def remove(_key); end

    # No-op method.
    # @return [nil] Always returns nil
    def remove_all; end

    # No-op method.
    # @return [nil] Always returns nil
    def clean; end
  end

  # Makes a new object of the cache.
  #
  # "sync" is whether the hash is thread-safe (`true`)
  # or not (`false`); it is recommended to leave this parameter untouched,
  # unless you really know what you are doing.
  #
  # If the <tt>dirty</tt> argument is set to <tt>true</tt>, a previously
  # calculated result will be returned if it exists, even if it is already expired.
  #
  # @param sync [Boolean] Whether the hash is thread-safe
  # @param dirty [Boolean] Whether to return expired values
  # @return [Zache] A new instance of the cache
  def initialize(sync: true, dirty: false)
    @hash = {}
    @sync = sync
    @dirty = dirty
    @mutex = Mutex.new
    @locks = {}
  end

  # Total number of keys currently in cache.
  #
  # @return [Integer] Number of keys in the cache
  def size
    sync { @hash.size }
  end

  # Gets the value from the cache by the provided key.
  #
  # If the value is not
  # found in the cache, it will be calculated via the provided block. If
  # the block is not given and the key doesn't exist or is expired, an exception will be raised
  # (unless <tt>dirty</tt> is set to <tt>true</tt>). The lifetime
  # must be in seconds. The default lifetime is huge, which means that the
  # key will never be expired.
  #
  # If the <tt>dirty</tt> argument is set to <tt>true</tt>, a previously
  # calculated result will be returned if it exists, even if it is already expired.
  #
  # @param key [Object] The key to retrieve from the cache
  # @param lifetime [Integer] Time in seconds until the key expires
  # @param dirty [Boolean] Whether to return expired values
  # @param eager [Boolean] Whether to return placeholder while working
  # @param placeholder [Object] The placeholder to return in eager mode
  # @yield Block to calculate the value if not in cache
  # @yieldreturn [Object] The value to cache
  # @return [Object] The cached value
  def get(key, lifetime: 2**32, dirty: false, placeholder: nil, eager: false, &block)
    if block_given?
      return cached(key) if dirt?(key, dirty)
      return eager(key, lifetime, placeholder, &block) if eager
      lock(key) { calc(key, lifetime, &block) }
    else
      fetch(key, dirty)
    end
  end

  # Checks whether the value exists in the cache by the provided key. Returns
  # TRUE if the value is here. If the key is already expired in the cache,
  # it will be removed by this method and the result will be FALSE.
  #
  # @param key [Object] The key to check in the cache
  # @param dirty [Boolean] Whether to consider expired values as existing
  # @return [Boolean] True if the key exists and is not expired (unless dirty is true)
  def exists?(key, dirty: false)
    sync do
      rec = @hash[key]
      if overdue?(key) && !dirty && !@dirty
        @hash.delete(key)
        rec = nil
      end
      !rec.nil?
    end
  end

  # Checks whether the key exists in the cache and is expired. If the
  # key is absent FALSE is returned.
  #
  # @param key [Object] The key to check in the cache
  # @return [Boolean] True if the key exists and is expired
  def expired?(key)
    sync { overdue?(key) }
  end

  # Returns the modification time of the key, if it exists.
  # If not, current time is returned.
  #
  # @param key [Object] The key to get the modification time for
  # @return [Time] The modification time of the key or current time if key doesn't exist
  def mtime(key)
    sync do
      rec = @hash[key]
      rec.nil? ? Time.now : rec[:start]
    end
  end

  # Is key currently locked doing something?
  #
  # @param [Object] key The key to check
  # @return [Boolean] True if the cache is locked
  def locked?(key)
    sync { @locks[key]&.locked? }
  end

  # Put a value into the cache.
  #
  # @param key [Object] The key to store the value under
  # @param value [Object] The value to store in the cache
  # @param lifetime [Integer] Time in seconds until the key expires (default: never expires)
  # @return [Object] The value stored
  def put(key, value, lifetime: 2**32)
    lock(key) do
      @hash[key] = { value: value, start: Time.now, lifetime: lifetime }
    end
  end

  # Removes the value from the cache, by the provided key. If the key is absent
  # and the block is provided, the block will be called.
  #
  # @param key [Object] The key to remove from the cache
  # @yield Block to call if the key is not found
  # @return [Object] The removed value or the result of the block
  def remove(key)
    lock(key) { @hash.delete(key) { yield if block_given? } }
    sync { @locks.delete(key) }
  end

  # Remove all keys from the cache.
  #
  # @return [Hash] Empty hash
  def remove_all
    sync do
      @hash = {}
      @locks = {}
    end
  end

  # Remove all keys that match the block.
  #
  # @yield [key] Block that should return true for keys to be removed
  # @yieldparam key [Object] The cache key to evaluate
  # @return [Integer] Number of keys removed
  def remove_by
    sync do
      count = 0
      @hash.each_key do |k|
        next unless yield(k)
        @hash.delete(k)
        @locks.delete(k)
        count += 1
      end
      count
    end
  end

  # Remove keys that are expired. This cleans up the cache by removing all keys
  # where the lifetime has been exceeded.
  #
  # @return [Integer] Number of keys removed
  def clean
    sync do
      count = 0
      @hash.delete_if do |key, _value|
        expired = overdue?(key)
        if expired
          @locks.delete(key)
          count += 1
        end
        expired
      end
      count
    end
  end

  # Returns TRUE if the cache is empty, FALSE otherwise.
  #
  # @return [Boolean] True if the cache is empty
  def empty?
    sync { @hash.empty? }
  end

  private

  # Checks if dirty value should be returned for a locked key
  # @param key [Object] The key to check
  # @param dirty [Boolean] Whether dirty reads are allowed
  # @return [Boolean] True if dirty value should be returned
  def dirt?(key, dirty)
    (dirty || @dirty) && locked?(key) && stale?(key)
  end

  # Checks if key has an expired value in cache
  # @param key [Object] The key to check
  # @return [Boolean] True if key exists and is expired
  def stale?(key)
    sync do
      !@hash[key].nil? && overdue?(key)
    end
  end

  # Gets the dirty cached value without recalculation
  # @param key [Object] The key to retrieve
  # @return [Object] The cached value
  def cached(key)
    sync { @hash[key][:value] }
  end

  # Handles eager mode get operation
  # @param key [Object] The key to retrieve
  # @param lifetime [Integer] Time in seconds until the key expires
  # @param placeholder [Object] The placeholder to return immediately
  # @yield Block that provides the value
  # @return [Object] The placeholder value
  def eager(key, lifetime, placeholder, &block)
    return sync { @hash[key][:value] } if sync { @hash.key?(key) }
    put(key, placeholder, lifetime: 0)
    spawn(key, lifetime, &block)
    placeholder
  end

  # Spawns a background thread to calculate the value
  # @param key [Object] The key to calculate for
  # @param lifetime [Integer] Time in seconds until the key expires
  # @yield Block that provides the value
  def spawn(key, lifetime, &block)
    Thread.new do
      lock(key) { calc(key, lifetime, &block) }
    rescue StandardError => e
      cleanup(key)
      raise(e)
    end
  end

  # Cleans up a key after calculation failure
  # @param key [Object] The key to clean up
  def cleanup(key)
    sync do
      @hash.delete(key)
      @locks.delete(key)
    end
  end

  # Gets value without a block (retrieval only mode)
  # @param key [Object] The key to retrieve
  # @param dirty [Boolean] Whether to return expired values
  # @return [Object] The cached value
  def fetch(key, dirty)
    sync do
      rec = @hash[key]
      if overdue?(key)
        return rec[:value] if dirty || @dirty
        @hash.delete(key)
        rec = nil
      end
      raise(StandardError, 'The key is absent in the cache') if rec.nil?
      rec[:value]
    end
  end

  # Calculates or retrieves a cached value for the given key.
  # @param key [Object] The key to store the value under
  # @param lifetime [Integer] Time in seconds until the key expires
  # @yield Block that provides the value if not cached
  # @return [Object] The cached or newly calculated value
  def calc(key, lifetime)
    rec = @hash[key]
    rec = nil if overdue?(key)
    if rec.nil?
      rec = { value: yield, start: Time.now, lifetime: lifetime }
      @hash[key] = rec
    end
    rec[:value]
  end

  # Internal method that checks if a key is expired without acquiring locks.
  # This should only be called from within a synchronized block.
  # @param key [Object] The key to check in the cache
  # @return [Boolean] True if the key exists and is expired
  def overdue?(key)
    rec = @hash[key]
    !rec.nil? && rec[:lifetime] && rec[:start] < Time.now - rec[:lifetime]
  end

  # Executes a block within a synchronized context if sync is enabled.
  # @param block [Proc] The block to execute
  # @yield The block to execute in a synchronized context
  # @return [Object] The result of the block
  def sync(&block)
    return yield unless @sync
    @mutex.synchronize(&block)
  end

  # Executes a block within a synchronized context if sync is enabled.
  # @param key [Object] The object to sync
  # @param block [Proc] The block to execute
  # @yield The block to execute in a synchronized context
  # @return [Object] The result of the block
  def lock(key, &block)
    return yield unless @sync
    @mutex.synchronize { @locks[key] ||= Mutex.new }.synchronize(&block)
  end
end
