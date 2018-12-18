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

require 'monitor'

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
  # Makes a new object of the cache.
  # "sync" is whether the hash is thread-safe (`true`)
  # or not (`false`); it is recommended to leave this parameter untouched,
  # unless you really know what you are doing.
  #
  # If the <tt>dirty</tt> argument is set to <tt>true</tt>, a previously
  # calculated result will be returned if it exists.
  def initialize(sync: true, dirty: false)
    @hash = {}
    @sync = sync
    @dirty = dirty
    @monitor = Monitor.new
  end

  # Gets the value from the cache by the provided key. If the value is not
  # found in the cache, it will be calculated via the provided block. If
  # the block is not given, an exception will be raised. The lifetime
  # must be in seconds. The default lifetime is huge, which means that the
  # key will never be expired.
  #
  # If the <tt>dirty</tt> argument is set to <tt>true</tt>, a previously
  # calculated result will be returned if it exists.
  def get(key, lifetime: 2**32, dirty: false)
    if block_given?
      if (dirty || @dirty) && locked? && key_expired?(key) && @hash.key?(key)
        return @hash[key][:value]
      end
      synchronized { calc(key, lifetime) { yield } }
    else
      rec = @hash[key]
      if key_expired?(key)
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
  def exists?(key)
    rec = @hash[key]
    if key_expired?(key)
      @hash.delete(key)
      rec = nil
    end
    !rec.nil?
  end

  # Is cache currently locked doing something?
  def locked?
    !@monitor.mon_try_enter { true }
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
  # and the block is provide, the block will be called.
  def remove(key)
    synchronized { @hash.delete(key) { yield if block_given? } }
  end

  # Remove all keys from the cache.
  def remove_all
    synchronized { @hash = {} }
  end

  # Remove keys that are expired.
  def clean
    synchronized { @hash.delete_if { |_key, value| key_expired?(value) } }
  end

  private

  def calc(key, lifetime)
    rec = @hash[key]
    rec = nil if key_expired?(key)
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
      @monitor.synchronize do
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

  def key_expired?(key)
    rec = @hash[key]
    !rec.nil? && rec[:start] < Time.now - rec[:lifetime]
  end
end
