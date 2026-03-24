# frozen_string_literal: true

module Jekyll
module Plugins
module PaginateV3
module Utils

# Small logging adapter that keeps pagination internals independent from
# Jekyll logger globals while still writing through `Jekyll.logger`.
#
# Usage:
# - call with `(message, level)` where `level` is `debug|info|warn|error`
# - debug messages are emitted only when `debug_enabled` is true
# - use `scoped_log_lambda` to override debug emission for one template
class Logger
	def initialize(debug_enabled:)
		@debug_enabled = !!debug_enabled
	end

	# Builds a logger callback that reuses the same info/warn/error routing
	# but applies a local debug override for one pagination scope.
	def scoped_log_lambda(debug_enabled:)
		lambda do |message, level = 'info'|
			call(message, level, debug_enabled: debug_enabled)
		end
	end

	# Uniform logging entry point used by model/builder callbacks.
	def call(message, level = 'info', debug_enabled: nil)
		case level.to_s
		when 'debug'
			debug(message, debug_enabled: debug_enabled)
		when 'warn'
			warn(message)
		when 'error'
			error(message)
		else
			info(message)
		end
	end

	# Writes a debug message if pagination debug mode is enabled.
	def debug(message, debug_enabled: nil)
		return unless debug_enabled?(debug_enabled)

		Jekyll.logger.info('Pagination:', "[debug] #{message}")
	end

	# Writes an informational message.
	def info(message)
		Jekyll.logger.info('Pagination:', message.to_s)
	end

	# Writes a warning message.
	def warn(message)
		Jekyll.logger.warn('Pagination:', message.to_s)
	end

	# Writes an error message.
	def error(message)
		Jekyll.logger.error('Pagination:', message.to_s)
	end

	private

	# Resolves whether debug output should be emitted for the current call.
	def debug_enabled?(debug_enabled)
		return @debug_enabled if debug_enabled.nil?

		!!debug_enabled
	end
end

end
end
end
end
