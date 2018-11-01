[![DevOps By Rultor.com](http://www.rultor.com/b/yegor256/zache)](http://www.rultor.com/p/yegor256/zache)
[![We recommend RubyMine](http://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![Build Status](https://travis-ci.org/yegor256/zache.svg)](https://travis-ci.org/yegor256/zache)
[![Gem Version](https://badge.fury.io/rb/zache.svg)](http://badge.fury.io/rb/zache)
[![Maintainability](https://api.codeclimate.com/v1/badges/c136afe340fa94f14696/maintainability)](https://codeclimate.com/github/yegor256/zache/maintainability)

It's a simple Ruby gem for in-memory cache.

First, install it:

```bash
$ gem install zache
```

Then, use it like this

```ruby
require 'zache'
zache = Zache.new
# Expires in 5 minutes
v = zache.get(:count, lifetime: 5 * 60) { expensive() }
```
That's it.

# How to contribute

Read [these guidelines](https://www.yegor256.com/2014/04/15/github-guidelines.html).
Make sure you build is green before you contribute
your pull request. You will need to have [Ruby](https://www.ruby-lang.org/en/) 2.3+ and
[Bundler](https://bundler.io/) installed. Then:

```
$ bundle update
$ rake
```

If it's clean and you don't see any error messages, submit your pull request.

# License

(The MIT License)

Copyright (c) 2018 Yegor Bugayenko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the 'Software'), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
