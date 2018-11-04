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

require 'minitest/autorun'
require 'threads'
require_relative '../lib/zache'

# Cache test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class ZacheTest < Minitest::Test
  def test_caches
    cache = Zache.new(sync: false)
    first = cache.get(:hey, lifetime: 5) { Random.rand }
    second = cache.get(:hey) { Random.rand }
    assert(first == second)
  end

  def test_caches_and_expires
    cache = Zache.new
    first = cache.get(:hey, lifetime: 0.01) { Random.rand }
    sleep 0.1
    second = cache.get(:hey) { Random.rand }
    assert(first != second)
  end

  def test_caches_in_threads
    cache = Zache.new
    Threads.new(10).assert(100) do
      cache.get(:hey, lifetime: 0.0001) { Random.rand }
    end
  end

  def test_get_with_raise_no_block
    cache = Zache.new
    error = assert_raises(RuntimeError) { cache.get(:hey, lifetime: 0.01) }

    assert_equal(error.message, 'A block is required')

    cache.get(:hey, lifetime: 0.01) { Random.rand }

    assert(true)
  end

  def test_key_exists
    cache = Zache.new
    cache.get(:hey) { Random.rand }
    exists_result = cache.exists?(:hey)
    not_exists_result = cache.exists?(:bye)
    assert(exists_result == true)
    assert(not_exists_result == false)
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

  def test_remove_absent_key
    cache = Zache.new
    cache.remove(:hey)
  end

  def test_check_and_remove
    cache = Zache.new
    cache.get(:hey, lifetime: 0) { Random.rand }
    assert(!cache.exists?(:hey))
  end
end
