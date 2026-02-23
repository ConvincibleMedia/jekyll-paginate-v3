source 'https://rubygems.org'

# Specify your gem's dependencies in jekyll-paginate-v3.gemspec
gemspec

if ENV["JEKYLL_VERSION"]
  gem "jekyll", "~> #{ENV["JEKYLL_VERSION"]}"
end

# adding dev-dependencies to Gemfile (instead of gemspec) allows calling
# `bundle exec [executable] [options]` more easily.
group :test do
  gem "rubocop", "~> 0.51.0"
  gem "rspec", "~> 3.13"
  gem "bigdecimal", "~> 3.1"

  # Prefer the documented local harness path, with a local workspace fallback.
  harness_path = File.expand_path("~/gems/jekyll-test-harness")
  unless File.directory?(harness_path)
    harness_path = File.expand_path("../jekyll-test-harness", __dir__)
  end
  gem "jekyll-test-harness", path: harness_path
end
