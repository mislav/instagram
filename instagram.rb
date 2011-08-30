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

  class OAuthRequest < Faraday::Middleware
    def initialize(app, options)
      super(app)
      @config = options[:config]
    end

    def call(env)
      unless env[:request][:oauth] == false
        params = %w[client_id client_secret access_token].each_with_object({}) do |key, hash|
          value = @config.send(key)
          hash[key] = value if value.present?
        end
        if env[:method] == :get
          url = env[:url]
          url.query_values = params.update(url.query_values || {})
          env[:url] = url
        else
          env[:body] = params.update(env[:body] || {})
        end
      end
      @app.call(env)
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
          b.use OAuthRequest, config: self
          b.request :url_encoded
          b.use Mashify
          b.response :raise_error
          b.use FaradayStack::ResponseJSON, content_type: 'application/json'
          b.use PreserveRawBody
          b.use FaradayStack::Caching, cache, strip_params: %w[access_token client_id client_secret] unless cache.nil?
          b.use FaradayStack::Instrumentation
          b.adapter Faraday.default_adapter
        end

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

  module OAuthMethods
    def authorization_url(options)
      connection.build_url '/oauth/authorize', client_id: client_id,
        redirect_uri: options[:return_to], response_type: 'code'
    end

    def get_access_token(options)
      connection.post '/oauth/access_token', code: options[:code],
        grant_type: 'authorization_code', redirect_uri: options[:return_to]
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
  extend OAuthMethods
  extend ApiMethods
end
