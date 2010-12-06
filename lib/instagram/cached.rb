require 'instagram'
require 'instagram/failsafe_store'

module Instagram
  module Cached
    extend Instagram
    
    class << self
      attr_accessor :cache
      
      def setup(cache_dir, options = {})
        self.cache = FailsafeStore.new(cache_dir, {
          namespace: 'instagram',
          exceptions: [Net::HTTPServerException, JSON::ParserError]
        }.update(options))
      end
      
      private
      def get_url(url)
        cache.fetch(url.to_s) { super }
      end
    end
    
  end
end
