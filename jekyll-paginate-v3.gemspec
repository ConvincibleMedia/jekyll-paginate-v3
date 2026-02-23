# Gem packaging metadata for jekyll-paginate-v3.
#
# This file is used by RubyGems/Bundler when the gem is built, installed, or
# resolved in a host Jekyll site. It declares versioning, dependencies, and the
# files that make up the published package.
lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'jekyll-paginate-v3/version'

Gem::Specification.new do |spec|
  spec.name = 'jekyll-paginate-v3'
  spec.version = Jekyll::Plugins::PaginateV3::VERSION
  spec.authors = ['Convincible']
  spec.email = ['development@convincible.media']

  spec.summary = 'Robust, flexible, configurable pagination for Jekyll websites.'
  spec.description = 'Paginate any collection, and filter or index by any frontmatter key.'
  spec.homepage = 'https://github.com/ConvincibleMedia/jekyll-paginate-v3'
  spec.license = 'LGPL-3.0-or-later'

  spec.files = Dir['lib/**/*.rb'] + %w[README.md]
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.4.0'
  spec.required_rubygems_version = ">= 2.7.0"

  spec.add_dependency 'jekyll', '>= 3.8.5', '< 5.0'

  spec.add_development_dependency 'pry', '~> 0.14'
  spec.add_development_dependency 'pry-byebug', '~> 3.10'
  spec.add_development_dependency 'rspec', '~> 3.13'
end
