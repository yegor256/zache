# frozen_string_literal: true

# (The MIT License)
#
# Copyright (c) 2018 Yegor Bugayenko
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
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Zache
  # Fake implementation that doesn't cache anything, but behaves like it
  # does. It implements all methods of the original class, but doesn't do
  # any caching. This is very useful for testing.
  class Fake
    def size
      1
    end

    def get(*)
      yield
    end

    def exists?(*)
      true
    end

    def locked?
      false
    end

    def put(*); end

    def remove(_key); end

    def remove_all; end

    def clean; end
  end

  # Makes a new object of the cache.
  #
  # "sync" is whether the hash is thread-safe (`true`)
  # or not (`false`); it is recommended to leave this parameter untouched,
  # unless you really know what you are doing.
  #
  # If the <tt>dirty</tt> argument is set to <tt>true</tt>, a previously
  # calculated result will be returned if it exists and is already expired.
  def initialize(sync: true, dirty: false)
    @hash = {}
    @sync = sync
    @dirty = dirty
    @mutex = Mutex.new
  end

  # Total number of keys currently in cache.
  def size
    @hash.size
  end

  # Gets the value from the cache by the provided key.
  #
  # If the value is not
  # found in the cache, it will be calculated via the provided block. If
  # the block is not given, an exception will be raised (unless <tt>dirty</tt>
  # is set to <tt>true</tt>). The lifetime
  # must be in seconds. The default lifetime is huge, which means that the
  # key will never be expired.
  #
  # If the <tt>dirty</tt> argument is set to <tt>true</tt>, a previously
  # calculated result will be returned if it exists and is already expired.
  def get(key, lifetime: 2**32, dirty: false)
    if block_given?
      if (dirty || @dirty) && locked? && expired?(key) && @hash.key?(key)
        return @hash[key][:value]
      end
      synchronized { calc(key, lifetime) { yield } }
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
  # TRUE if the value is here. If the key is already expired in the hash,
  # it will be removed by this method and the result will be FALSE.
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
  def expired?(key)
    rec = @hash[key]
    !rec.nil? && rec[:start] < Time.now - rec[:lifetime]
  end

  # Returns the modification time of the key, if it exists.
  # If not, current time is returned.
  def mtime(key)
    rec = @hash[key]
    rec.nil? ? Time.now : rec[:start]
  end

  # Is cache currently locked doing something?
  def locked?
    @mutex.locked?
  end

  # Put a value into the cache.
  def put(key, value, lifetime: 2**32)
    synchronized do
      @hash[key] = {
        value: value,
        start: Time.now,
        lifetime: lifetime
      }
    end
  end

  # Removes the value from the hash, by the provied key. If the key is absent
  # and the block is provided, the block will be called.
  def remove(key)
    synchronized { @hash.delete(key) { yield if block_given? } }
  end

  # Remove all keys from the cache.
  def remove_all
    synchronized { @hash = {} }
  end

  # Remove all keys that match the block.
  def remove_by
    synchronized do
      @hash.keys.each do |k|
        @hash.delete(k) if yield(k)
      end
    end
  end

  # Remove keys that are expired.
  def clean
    synchronized { @hash.delete_if { |key, _value| expired?(key) } }
  end

  def empty?
    @hash.empty?
  end

  private

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

  def synchronized
    if @sync
      @mutex.synchronize do
        # I don't know why, but if you remove this line, the tests will
        # break. It seems to me that there is a bug in Ruby. Let's try to
        # fix it or find a workaround and remove this line.
        sleep 0.00001
        yield
      end
    else
      yield
    end
  end
end
