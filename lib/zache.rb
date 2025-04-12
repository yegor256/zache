# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
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
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
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
    # @param [Object] key Ignored
    # @param [Hash] opts Ignored
    # @yield Block that provides the value
    # @return [Object] The result of the block
    def get(*)
      yield
    end

    # Always returns true regardless of the key.
    # @param [Object] key Ignored
    # @param [Hash] opts Ignored
    # @return [Boolean] Always returns true
    def exists?(*)
      true
    end

    # Always returns false.
    # @return [Boolean] Always returns false
    def locked?
      false
    end

    # No-op method that ignores the input.
    # @param [Object] key Ignored
    # @param [Object] value Ignored
    # @param [Hash] opts Ignored
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
  end

  # Total number of keys currently in cache.
  #
  # @return [Integer] Number of keys in the cache
  def size
    @hash.size
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
  # @param eager [Boolean] Whether to return placeholder while working?
  # @param placeholder [Object] The placeholder to return in eager mode
  # @yield Block to calculate the value if not in cache
  # @yieldreturn [Object] The value to cache
  # @return [Object] The cached value
  def get(key, lifetime: 2**32, dirty: false, placeholder: nil, eager: false, &block)
    if block_given?
      return @hash[key][:value] if (dirty || @dirty) && locked? && expired?(key) && @hash.key?(key)
      if eager
        return @hash[key][:value] if @hash.key?(key)
        put(key, placeholder, lifetime: 0)
        Thread.new do
          synchronized do
            calc(key, lifetime, &block)
          end
        end
        placeholder
      else
        synchronized do
          calc(key, lifetime, &block)
        end
      end
    else
      rec = @hash[key]
      if expired?(key)
        return rec[:value] if dirty || @dirty
        @hash.delete(key)
        rec = nil
      end
      raise 'The key is absent in the cache' if rec.nil?
      rec[:value]
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
    rec = @hash[key]
    if expired?(key) && !dirty && !@dirty
      @hash.delete(key)
      rec = nil
    end
    !rec.nil?
  end

  # Checks whether the key exists in the cache and is expired. If the
  # key is absent FALSE is returned.
  #
  # @param key [Object] The key to check in the cache
  # @return [Boolean] True if the key exists and is expired
  def expired?(key)
    rec = @hash[key]
    !rec.nil? && rec[:start] < Time.now - rec[:lifetime]
  end

  # Returns the modification time of the key, if it exists.
  # If not, current time is returned.
  #
  # @param key [Object] The key to get the modification time for
  # @return [Time] The modification time of the key or current time if key doesn't exist
  def mtime(key)
    rec = @hash[key]
    rec.nil? ? Time.now : rec[:start]
  end

  # Is cache currently locked doing something?
  #
  # @return [Boolean] True if the cache is locked
  def locked?
    @mutex.locked?
  end

  # Put a value into the cache.
  #
  # @param key [Object] The key to store the value under
  # @param value [Object] The value to store in the cache
  # @param lifetime [Integer] Time in seconds until the key expires (default: never expires)
  # @return [Object] The value stored
  def put(key, value, lifetime: 2**32)
    synchronized do
      @hash[key] = {
        value: value,
        start: Time.now,
        lifetime: lifetime
      }
    end
  end

  # Removes the value from the cache, by the provided key. If the key is absent
  # and the block is provided, the block will be called.
  #
  # @param key [Object] The key to remove from the cache
  # @yield Block to call if the key is not found
  # @return [Object] The removed value or the result of the block
  def remove(key)
    synchronized { @hash.delete(key) { yield if block_given? } }
  end

  # Remove all keys from the cache.
  #
  # @return [Hash] Empty hash
  def remove_all
    synchronized { @hash = {} }
  end

  # Remove all keys that match the block.
  #
  # @yield [key] Block that should return true for keys to be removed
  # @yieldparam key [Object] The cache key to evaluate
  # @return [Integer] Number of keys removed
  def remove_by
    synchronized do
      count = 0
      @hash.each_key do |k|
        if yield(k)
          @hash.delete(k)
          count += 1
        end
      end
      count
    end
  end

  # Remove keys that are expired. This cleans up the cache by removing all keys
  # where the lifetime has been exceeded.
  #
  # @return [Integer] Number of keys removed
  def clean
    synchronized do
      size_before = @hash.size
      @hash.delete_if { |key, _value| expired?(key) }
      size_before - @hash.size
    end
  end

  # Returns TRUE if the cache is empty, FALSE otherwise.
  #
  # @return [Boolean] True if the cache is empty
  def empty?
    @hash.empty?
  end

  private

  # Calculates or retrieves a cached value for the given key.
  # @param key [Object] The key to store the value under
  # @param lifetime [Integer] Time in seconds until the key expires
  # @yield Block that provides the value if not cached
  # @return [Object] The cached or newly calculated value
  def calc(key, lifetime)
    rec = @hash[key]
    rec = nil if expired?(key)
    if rec.nil?
      @hash[key] = {
        value: yield,
        start: Time.now,
        lifetime: lifetime
      }
    end
    @hash[key][:value]
  end

  # Executes a block within a synchronized context if sync is enabled.
  # @param block [Proc] The block to execute
  # @yield The block to execute in a synchronized context
  # @return [Object] The result of the block
  def synchronized(&block)
    if @sync
      @mutex.synchronize(&block)
    else
      yield
    end
  end
end
