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

# Cache.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Zache
  def initialize(sync: true)
    @hash = {}
    @sync = sync
    @mutex = Mutex.new
  end

  def get(key, lifetime: 60 * 60)
    if @sync
      @mutex.synchronize do
        calc(key, lifetime) { yield }
      end
    else
      calc(key, lifetime) { yield }
    end
  end

  def exists?(key)
    @hash.key?(key)
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
