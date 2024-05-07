require 'open-uri'
require 'base64'
require 'json'

module Klaviyo
  class KlaviyoError < StandardError; end

  class Client
    def initialize(api_key, url = 'https://a.klaviyo.com/')
      @api_key = api_key
      @url = url
    end

    def track(event, kwargs = {})
      defaults = {:id => nil, :email => nil, :properties => {}, :customer_properties => {}, :time => nil}
      kwargs = defaults.merge(kwargs)

      if kwargs[:email].to_s.empty? and kwargs[:id].to_s.empty?
        raise KlaviyoError.new('You must identify a user by email or ID')
      end

      customer_properties = kwargs[:customer_properties]
      customer_properties[:email] = kwargs[:email] unless kwargs[:email].to_s.empty?
      customer_properties[:id] = kwargs[:id] unless kwargs[:id].to_s.empty?

      time = kwargs[:time].strftime("%FT%T") if kwargs[:time]
      value = kwargs[:properties]["value"] || 0

      payload = {
        :data => {
          :type => 'event',
          :attributes => {
            "properties" => kwargs[:properties], 
            "time" => time, 
            "value" => value, 
            "value_currency" => "USD", 
            "metric" => {"data"=>{"type"=>"metric", "attributes"=>{"name"=>event}}},
            "profile" => {"data"=>{"type"=>"profile", "attributes"=>customer_properties}}
          }
        }
      }

      puts "\n\n\npayload:"
      puts payload
      puts "\n\n\n"

      RestClient.post("#{@url}api/events", payload.to_json, {accept: :json, revision: '2024-02-15', content_type: :json, authorization: "Klaviyo-API-Key #{@api_key}"}) do |response, request, result, &block|
        if response.code == 202
          return true
        else
          raise KlaviyoError.new(JSON.parse(response))
        end
      end
    end

    def track_once(event, opts = {})
      opts.update('__track_once__' => true)
      track(event, opts)
    end

    def identify(base_attributes = {}, custom_properties = {})
      if base_attributes["email"].to_s.empty?
        raise KlaviyoError.new('You must identify a user by email or ID')
      end

      payload = {
        :data => {
          :type => 'profile',
          :attributes => {
            "email" => base_attributes["email"],
            "first_name" => base_attributes["first_name"],
            "last_name" => base_attributes["last_name"],
            "location" => base_attributes["location"],
            "properties" => custom_properties
          }
        } 
      }

      puts "\n\n\npayload:"
      puts payload
      puts "\n\n\n"
      
      RestClient.post("#{@url}api/profile-import", payload.to_json, {accept: :json, revision: '2024-02-15', content_type: :json, authorization: "Klaviyo-API-Key #{@api_key}"}) do |response, request, result, &block|
        if response.code == 200 || response.code == 201
          puts "success"
          puts "response code: #{response.code}"
          puts "response:"
          JSON.parse(response)
        else
          raise KlaviyoError.new(JSON.parse(response))
        end
      end
    end

    def lists
      RestClient.get("#{@url}api/lists", params: {api_key: @api_key}) do |response, request, result, &block|
        if response.code == 200
          JSON.parse(response)
        else
          raise KlaviyoError.new(response)
        end
      end
    end

    def add_to_list(email, list_id, properties, confirm_optin)
      payload = {
        api_key: @api_key,
        profiles: [
          { email: email }.merge(properties)
        ]
      }

      sub_or_members = confirm_optin ? 'subscribe' : 'members'
      RestClient.post("#{@url}api/v2/list/#{list_id}/#{sub_or_members}", payload.to_json, {content_type: :json, accept: :json}) do |response, request, result, &block|
        if response.code == 200
          JSON.parse(response)
        else
          raise KlaviyoError.new(JSON.parse(response))
        end
      end
    end

    def get_profile(id)
      RestClient.get("#{@url}api/v1/person/#{id}", params: {api_key: @api_key}) do |response, request, result, &block|
        if response.code == 200
          JSON.parse(response)
        else
          raise KlaviyoError.new(response)
        end
      end
    end

    def update_profile(id, properties)
      payload = properties.merge(api_key: @api_key)
      RestClient.put("#{@url}api/v1/person/#{id}", payload) do |response, request, result, &block|
        if response.code == 200
          JSON.parse(response)
        else
          raise KlaviyoError.new(JSON.parse(response))
        end
      end
    end

    private

    def build_params(params)
      "data=#{CGI.escape Base64.encode64(JSON.generate(params)).gsub(/\n/,'')}"
    end

    def request(path, params)
      url = "#{@url}#{path}?#{params}"
      open(url).read == '1'
    end
  end
end
