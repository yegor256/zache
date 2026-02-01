# In Memory Cache for Ruby

[![EO principles respected here](https://www.elegantobjects.org/badge.svg)](https://www.elegantobjects.org)
[![DevOps By Rultor.com](https://www.rultor.com/b/yegor256/zache)](https://www.rultor.com/p/yegor256/zache)
[![We recommend RubyMine](https://www.elegantobjects.org/rubymine.svg)](https://www.jetbrains.com/ruby/)

[![rake](https://github.com/yegor256/zache/actions/workflows/rake.yml/badge.svg)](https://github.com/yegor256/zache/actions/workflows/rake.yml)
[![Gem Version](https://badge.fury.io/rb/zache.svg)](https://badge.fury.io/rb/zache)
[![Yard Docs](https://img.shields.io/badge/yard-docs-blue.svg)](https://rubydoc.info/github/yegor256/zache/master/frames)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/yegor256/zache/blob/master/LICENSE.txt)
[![Test Coverage](https://img.shields.io/codecov/c/github/yegor256/zache.svg)](https://codecov.io/github/yegor256/zache?branch=master)
[![Hits-of-Code](https://hitsofcode.com/github/yegor256/zache)](https://hitsofcode.com/view/github/yegor256/zache)

This is a simple Ruby gem for in-memory caching.
Read this [blog post] to understand what Zache is designed for.

First, install it:

```bash
gem install zache
```

Then, use it like this:

```ruby
require 'zache'
zache = Zache.new
# Expires in 5 minutes
v = zache.get(:count, lifetime: 5 * 60) { expensive_calculation() }
```

If you omit the `lifetime` parameter or set it to `nil`,
  the key will never expire.

By default `Zache` is thread-safe.
It locks the entire cache on each `get` call.
You can turn that off by using the `sync` argument:

```ruby
zache = Zache.new(sync: false)
v = zache.get(:count) { expensive_calculation() }
```

You may use "dirty" mode, which will return
  an expired value while calculation is in progress.
For example, if you have a value in the cache that's expired,
  and you call `get` with a long-running block, the thread waits.
If another thread calls `get` again, that second thread won't wait,
  but will receive the expired value from the cache.
This is a very convenient mode for situations
  where absolute data accuracy is less important than performance:

```ruby
zache = Zache.new(dirty: true)
# Or enable dirty mode for a specific get call
value = zache.get(:key, dirty: true) { expensive_calculation() }
```

You may use "eager" mode with a placeholder value to return immediately
  while the calculation happens in the background.
The cache returns the placeholder instantly and spawns
  a thread to calculate the actual value.
This is useful when you need to avoid blocking
  while expensive operations complete:

```ruby
# Returns 0 immediately, calculates in background
value = zache.get(:key, eager: true, placeholder: 0) { expensive_calculation() }
```

The entire API is [documented][rubydoc].
Here are some additional useful methods:

```ruby
# Check if a key exists
zache.exists?(:key)

# Remove a key
zache.remove(:key)

# Remove all keys
zache.remove_all

# Remove keys that match a condition
zache.remove_by { |key| key.to_s.start_with?('temp_') }

# Clean up expired keys
zache.clean

# Check if cache is empty
zache.empty?
```

## How to contribute

Read these [guidelines].
Make sure your build is green before you contribute your pull request.
You will need to have [Ruby](https://www.ruby-lang.org/en/) 2.3+ and
  [Bundler](https://bundler.io/) installed.
Then:

```bash
bundle update
bundle exec rake
```

If it's clean and you don't see any error messages, submit your pull request.

[blog post]: https://www.yegor256.com/2019/02/05/zache.html
[rubydoc]: https://www.rubydoc.info/github/yegor256/zache/master/Zache
[guidelines]: https://www.yegor256.com/2014/04/15/github-guidelines.html
