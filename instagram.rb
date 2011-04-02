require 'faraday_stack'
require 'hashie/mash'

module Instagram
  module Configuration
    attr_accessor :client_id, :client_secret, :access_token, :cache
  
    def configure
      yield self
    end
  end
  
  class Mashify < Faraday::Response::Middleware
    def on_complete(env)
      super if Hash === env[:body]
    end
    
    def parse(body)
      Hashie::Mash.new(body)
    end
  end
  
  class PreserveRawBody < Faraday::Response::Middleware
    def on_complete(env)
      env[:raw_body] = env[:body]
    end
  end
  
  module Connection
    def connection
      @connection ||= begin
        conn = Faraday.new('https://api.instagram.com/v1/') do |b|
          b.use Mashify
          b.use FaradayStack::ResponseJSON, content_type: 'application/json'
          b.use PreserveRawBody
          b.use FaradayStack::Caching, cache, strip_params: %w[access_token client_id] unless cache.nil?
          b.response :raise_error
          b.use FaradayStack::Instrumentation
          b.adapter Faraday.default_adapter
        end
      
        # conn.token_auth access_token unless access_token.nil?
        conn.params['access_token'] = access_token unless access_token.nil?
        conn.params['client_id'] = client_id
        conn.headers['User-Agent'] = 'instagram.heroku.com ruby client'
      
        conn
      end
    end
    
    def get(path, params = nil)
      connection.get(path) do |request|
        request.params = params if params
      end
    end
  end
  
  module ApiMethods
    def get(path, params = nil)
      raw = params && params.delete(:raw)
      response = super
      raw ? response.env[:raw_body] : response.body.data
    end
    
    def user(user_id, *args)
      get("users/#{user_id}", *args)
    end
  
    def user_recent_media(user_id, *args)
      get("users/#{user_id}/media/recent", *args)
    end
  
    def media_popular(*args)
      get("media/popular", *args)
    end
  
    def tag_search(query, params = {})
      get("tags/search", params.merge(:q => query))
    end
  
    def tag_recent_media(tag, *args)
      get("tags/#{tag}/media/recent", *args)
    end
  end
  
  extend Configuration
  extend Connection
  extend ApiMethods
end
