require 'httparty'

module SpecUtils
  class Utils
    class << self
      def get(path)
        HTTParty.get("http://127.0.0.1:9292/#{path}")
      end

      def post(path)
        HTTParty.post("http://127.0.0.1:9292/#{path}")
      end

      def put(path)
        HTTParty.put("http://127.0.0.1:9292/#{path}")
      end
    end
  end
end
