require 'active_support/cache'

module Instagram
  class FailsafeStore < ActiveSupport::Cache::FileStore
    # Reuses the stale cache if a known exception occurs while yielding to the block.
    # The list of exception classes is read from the ":exceptions" array.
    def fetch(name, options = nil)
      options = merged_options(options)
      key = namespaced_key(name, options)
      entry = unless options[:force]
        instrument(:read, name, options) do |payload|
          payload[:super_operation] = :fetch if payload
          read_entry(key, options)
        end
      end

      if entry and not entry.expired?
        instrument(:fetch_hit, name, options) { |payload| }
        entry.value
      else
        reusing_stale = false
        
        result = begin
          instrument(:generate, name, options) do |payload|
            yield
          end
        rescue
          if entry and ignore_exception?($!)
            reusing_stale = true
            instrument(:reuse_stale, name, options) do |payload|
              payload[:exception] = $! if payload
              entry.value
            end
          else
            # TODO: figure out if deleting entries is ever necessary
            # delete_entry(key, options) if entry
            raise
          end
        end
        
        write(name, result, options) unless reusing_stale
        result
      end
    end
    
    private
    
    def ignore_exception?(ex)
      options[:exceptions] && options[:exceptions].any? { |klass|
        if klass.respond_to?(:to_str)
          ex.class.name == klass.to_str
        else
          ex.is_a? klass
        end
      }
    end
  end
end
