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
        class Logger
          def initialize(debug_enabled:)
            @debug_enabled = !!debug_enabled
          end

          # Uniform logging entry point used by model/builder callbacks.
          def call(message, level = 'info')
            case level.to_s
            when 'debug'
              debug(message)
            when 'warn'
              warn(message)
            when 'error'
              error(message)
            else
              info(message)
            end
          end

          # Writes a debug message if pagination debug mode is enabled.
          def debug(message)
            return unless @debug_enabled

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
        end
      end
    end
  end
end
