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
  # Makes a new object of the cache.
  # "sync" is whether the hash is thread-safe (`true`)
  # or not (`false`); it is recommended to leave this parameter untouched,
  # unless you really know what you are doing.
  def initialize(sync: true)
    @hash = {}
    @sync = sync
    @mutex = Mutex.new
  end

  # Gets the value from the cache by the provided key. If the value is not
  # found in the cache, it will be calculated via the provided block. If
  # the block is not given, an exception will be raised.
  def get(key, lifetime: 60 * 60)
    raise 'A block is required' unless block_given?

    calc_lambda = -> { calc(key, lifetime) { yield } }

    return calc_lambda.call unless @sync

    @mutex.synchronize { calc_lambda.call } if @sync
  end

  # Checks whether the value exists in the cache by the provided key. Returns
  # TRUE if the value is here. If the key is already expired in the hash,
  # it will be removed by this method and the result will be FALSE.
  def exists?(key)
    rec = @hash[key]
    if !rec.nil? && rec[:start] < Time.now - rec[:lifetime]
      @hash.delete(key)
      rec = nil
    end
    !rec.nil?
  end

  # Removes the value from the hash, by the provied key. If the key is absent
  # and the block is provide, the block will be called.
  def remove(key)
    if @sync
      @mutex.synchronize do
        @hash.delete(key) { yield if block_given? }
      end
    else
      @hash.delete(key) { yield if block_given? }
    end
  end

  private

  def calc(key, lifetime)
    rec = @hash[key]
    rec = nil if !rec.nil? && rec[:start] < Time.now - rec[:lifetime]
    if rec.nil?
      @hash[key] = {
        value: yield,
        start: Time.now,
        lifetime: lifetime
      }
    end
    @hash[key][:value]
  end
end
