# Ruby Style Guide

* When writing code that has nested modules:
	* Collapse indentation where there is no code at a nesting level (other than to contain the next level).
	* Put one clear line around the module/class that actually has code and begins indentation.
	* Has code = contains methods/constants/procedural code/etc., contains a class or contains more than one module.
	* Example:

		```ruby
		module Jekyll
		module Plugins
		module PaginateV3

		module Utils
			# Start indentation because this module finally contains code (a class)
			class << self
				def example; end
			end
		end

		end
		end
		end
		```
* Use tabs for indentation, using indentation for logical nesting.
* When indentation is for aesthetics (to line code up for readability), tab to the logical level, then continue with spaces. E.g.

  ```ruby
  def example
  	if true
  		if a ||
  		   b ||
  		   c
  			return false
  		end
  	end
  end
  ```