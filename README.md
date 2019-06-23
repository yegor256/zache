[![EO principles respected here](https://www.elegantobjects.org/badge.svg)](https://www.elegantobjects.org)
[![DevOps By Rultor.com](http://www.rultor.com/b/yegor256/zache)](http://www.rultor.com/p/yegor256/zache)
[![We recommend RubyMine](https://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![Build Status](https://travis-ci.org/yegor256/zache.svg)](https://travis-ci.org/yegor256/zache)
[![Build status](https://ci.appveyor.com/api/projects/status/7eday736u9phnjiy?svg=true)](https://ci.appveyor.com/project/yegor256/zache)
[![Gem Version](https://badge.fury.io/rb/zache.svg)](http://badge.fury.io/rb/zache)
[![Maintainability](https://api.codeclimate.com/v1/badges/c136afe340fa94f14696/maintainability)](https://codeclimate.com/github/yegor256/zache/maintainability)
[![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](http://rubydoc.info/github/yegor256/zache/master/frames)

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/yegor256/zache/blob/master/LICENSE.txt)
[![Test Coverage](https://img.shields.io/codecov/c/github/zache/pgtk.svg)](https://codecov.io/github/yegor256/zache?branch=master)
[![Hits-of-Code](https://hitsofcode.com/github/yegor256/zache)](https://hitsofcode.com/view/github/yegor256/zache)

It's a simple Ruby gem for in-memory cache.
Read [this blog post](https://www.yegor256.com/2019/02/05/zache.html)
to understand what Zache is for.

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

By default `Zache` is thread-safe. It locks the entire cache on each
`get` call. You turn that off by using `sync` argument:

```ruby
zache = Zache.new(sync: false)
v = zache.get(:count) { expensive() }
```

You may use "dirty" mode, which will return you an expired value, while
calculation is waiting. Say, you have something in the cache, but it's
expired. Then, you call `get` with a long running block. The thread waits,
while another one calls `get` again. That second thread won't wait, but will
receive what's left in the cache. This is a very convenient mode for situations
when you don't really care about data accuracy, but performance is an issue.

The entire API is documented [here](https://www.rubydoc.info/github/yegor256/zache/master/Zache)
(there are many other convenient methods).

That's it.

## How to contribute

Read [these guidelines](https://www.yegor256.com/2014/04/15/github-guidelines.html).
Make sure you build is green before you contribute
your pull request. You will need to have [Ruby](https://www.ruby-lang.org/en/) 2.3+ and
[Bundler](https://bundler.io/) installed. Then:

```
$ bundle update
$ bundle exec rake
```

If it's clean and you don't see any error messages, submit your pull request.
