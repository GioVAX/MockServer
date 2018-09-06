# rubocop:disable Style/ClassVars

require 'json'
require 'grape'
require 'socket'
require 'yaml'
require 'httparty'
require 'grape_logging'

require_relative 'bootup_server_command'

# To prevent Puma from choking on a response with status 204 and non empty body
Rack::Utils::STATUS_WITH_NO_ENTITY_BODY = Set.new

module MockBackendHelpers
  def analytics_request?
    request.fullpath.include?('/eluminate')
  end
end

module MockBackend
  class API < Grape::API
    include Grape::Extensions::Hash::ParamBuilder

    # Uncomment the following statement to enable detailed logging
    # use GrapeLogging::Middleware::RequestLogger,
    #     logger: logger,
    #     include: [GrapeLogging::Loggers::Response.new,
    #               GrapeLogging::Loggers::FilterParameters.new,
    #               GrapeLogging::Loggers::ClientEnv.new,
    #               GrapeLogging::Loggers::RequestHeaders.new]

    content_type :xml, 'application/xml'
    content_type :json, 'application/json'
    content_type :binary, 'application/octet-stream'
    content_type :txt, 'text/plain'

    default_format :txt

    helpers MockBackendHelpers

    XML_ROOT_NAME = 'XML_ROOT_NAME'.freeze

    formatter :xml, lambda { |object, env|
      if object.is_a?(String)
        object
      elsif !object.nil?
        object.to_xml(root: env[XML_ROOT_NAME])
      end
    }

    before do
      # Ignore setting endpoints
      unless API.ignore_request? env['REQUEST_PATH']
        # Store requests
        analytics_request? ? @@analytics_requests << request : @@requests << request

        # Delay the response in seconds
        sleep @@forced_response_delay unless @@forced_response_delay.nil?

        # Respond with type
        content_type @@forced_response_type unless @@forced_response_type.nil?

        # Respond with HTTP status
        status @@forced_response_status unless @@forced_response_status.nil?

        # Respond with body
        body @@forced_response_body unless @@forced_response_body.nil?
      end

      params['mocksrv_root'] = env['SERVER_NAME'] + (env['SERVER_PORT'].empty? ? '' : ":#{env['SERVER_PORT']}")
    end

    # Root endpoint
    get '/' do
      content_type 'text/plain'
      body 'Up and running...'
    end

    route :any, '*path' do
      endpoint = API.find_matching_endpoint(env['REQUEST_URI'][1..-1])

      # Error if no endpoint matches the request
      if endpoint.nil? || endpoint[:match].nil?

        # Uncomment the following line to return an error for non-matching requests
        error!("Endpoint <#{params[:path]}> unknown", 404)

        # Uncomment the following code to have a debug printout for non-matching requests
        # status 404
        # break {
        #     resource: 'unknown',
        #     params: params,
        #     route: route,
        #     options: options,
        #     request: request,
        #     session: request.session,
        #     session_keys: request.session.keys,
        #     session_values: request.session.values,
        #     header: request.headers,
        #     env: env
        # }

        break
      end

      config = API.apply_dynamic_configuration(params[:path], endpoint[:cfg])
      match = endpoint[:match]

      # Check the request HTTP method is allowed by configuration
      unless API.request_method_allowed?(config, env['REQUEST_METHOD'])
        error!("Endpoint <#{params[:path]}> accepts methods <#{API.config_method config}>" \
                 " - Request method was <#{env['REQUEST_METHOD']}>", 401)
      end

      sleep config[:delay] unless (config[:delay] || 0).zero?

      content_type API.set_up_response(config, env)

      body API.generate_body(env['REQUEST_URI'], config, params, match)
      status config[:status] unless config[:status].nil?
    end

    def self.set_up_response(config, env)
      if (config[:content_type] || 'json').include? 'json'
        'application/json'
      elsif config[:content_type].include? 'xml'
        env[XML_ROOT_NAME] = config[:xml_root]

        content_type :xml, config[:content_type]
        config[:content_type]
      end
    end

    def self.find_matching_endpoint(path)
      @@endpoints.reduce(nil) do |reduce, config|
        reduce = { cfg: config, match: config[:regex].match(path) }
        break reduce unless reduce[:match].nil?
      end
    end

    def self.display_status(_ = nil, _ = nil, _ = nil)
      {
        response_delay: @@forced_response_delay,
        forced_type: @@forced_response_type,
        forced_status: @@forced_response_status,
        forced_body: @@forced_response_body,
        endpoints: display_configured_endpoints,
        dynamic: @@dynamic_config
      }
    end

    def self.display_analytics_requests(_ = nil, _ = nil, _ = nil)
      @@analytics_requests.map(&:fullpath)
    end

    def self.display_requests(_ = nil, _ = nil, _ = nil)
      @@requests.map(&:fullpath)
    end

    def self.apply_dynamic_configuration(path, config)
      dyn_config = (config[:allow_dynamic_config] || true)

      if dyn_config && (change = extract_matching_dynamic_config(path))
        config.merge(change)
      else
        config
      end
    end

    def self.web_add_dynamic_configuration(_, params, _)
      add_dynamic_configuration params
    end

    def self.add_dynamic_configuration(config)
      if remove_sticky_config? config
        @@dynamic_config.delete_if { |item| item[:uri] == config[:uri] && (item[:sticky] || false) }
      else
        @@dynamic_config.push normalize_endpoint_config(config)
      end
    end

    def self.remove_sticky_config?(config)
      (config[:sticky] || false) && (config.keys - %i[uri sticky path]).empty?
    end

    def self.extract_matching_dynamic_config(path)
      idx = @@dynamic_config.index { |dc| dc[:uri].nil? || dc[:regex].match(path) }

      return nil if idx.nil?

      dyn_cfg = @@dynamic_config[idx]
      @@dynamic_config.delete_at(idx) unless dyn_cfg[:sticky]

      return dyn_cfg if dyn_cfg[:regex].nil?

      dyn_cfg[:params] = merge_regex_params(dyn_cfg, path)
      dyn_cfg
    end

    def self.merge_regex_params(dyn_cfg, path)
      match_params = get_params_from_regex_match(dyn_cfg[:regex].match(path))
      dyn_cfg[:params].nil? ? match_params : dyn_cfg[:params].merge(match_params)
    end

    def self.request_method_allowed?(config, method)
      config_method(config).include? method
    end

    def self.merge_params(config, params, match)
      ret = params

      config_params = config[:params]
      ret = config_params.merge(ret) unless config_params.nil?

      match_params = get_params_from_regex_match(match)
      ret = match_params.merge(ret) unless match_params.nil?

      ret
    end

    def self.get_params_from_regex_match(match)
      match.names.each_with_object({}) { |name, hash| hash.store(name, match[name]) }
    end

    def self.generate_body(uri, config, params, match)
      if config[:generate_response].nil?
        merged_params = merge_params(config, params, match)
        body = API.standard_body(config, merged_params)
      else
        body = API.bespoke_body(config, params, match)
      end

      store_response_body(uri, body) unless config[:administrative]

      body
    end

    def self.standard_body(config, params)
      return if config[:response].nil?

      load_response_file config[:response], params
    end

    def self.bespoke_body(config, params, match)
      class_method = config[:generate_response].split '.'

      clazz = class_method[0].split('::').inject(Object) { |mod, class_name| mod.const_get(class_name) }

      clazz.send(class_method[-1], config, params, match)
    end

    def self.test_bespoke(config, params, match)
      {
        resource: 'debug',
        config: config,
        params: params,
        match: match,
        analytics_requests: @@analytics_requests
      }
    end

    def self.replace_params(text, params)
      params.each_key { |key| text.gsub! "%{#{key}}", params[key].to_s } unless params.nil?
      text
    end

    # Called after every scenario
    def self.init(_ = nil, _ = nil, _ = nil)
      @@requests = []
      @@responses = {}
      @@analytics_requests = []

      @@forced_response_delay = nil
      @@forced_response_type = nil
      @@forced_response_status = nil
      @@forced_response_body = nil

      @@dynamic_config = []
    end

    # Force responses
    def self.set_forced_response(_ = nil, params = {}, _ = nil)
      @@forced_response_body = null_or_empty?(params[:body]) ? nil : JSON.parse(params[:body])
      @@forced_response_status = null_or_empty?(params[:status]) ? nil : params[:status].to_i
      @@forced_response_type = null_or_empty?(params[:type]) ? nil : params[:type]
      @@forced_response_delay = null_or_empty?(params[:delay]) ? nil : params[:delay].to_i

      params || {}
    end

    def self.null_or_empty?(text)
      text.nil? || text.empty?
    end

    def self.load_response_file(file, params)
      extensions = [nil, 'json', 'xml']

      extensions.map do |ext|
        filepath = file_path file, ext
        next unless File.exist? filepath

        content = File.read(filepath)
        next if content.nil?

        response = replace_params(content, params)
        ((ext || File.extname(file)[1..-1]) == 'json' ? JSON.parse(response) : response)
      end
        .find { |cnt| !cnt.nil? }
    end

    def self.content_with_params_replaced(file, params, ext = nil)
      content = file_content(file, ext)
      replace_params(content, params) unless content.nil?
    end

    def self.file_path(file, ext)
      extension = ext.nil? ? '' : ".#{ext}"
      "#{File.dirname(__FILE__)}/api_responses/#{file}#{extension}"
    end

    def self.file_content(file, ext)
      filepath = file_path(file, ext)
      File.read(filepath) if File.exist? filepath
    end

    # Returns all made requests
    def self.requests
      @@requests.clone
    end

    def self.store_response_body(uri, body)
      @@responses["#{uri} - #{Time.now.strftime('%Y%m%d %H:%M:%S')}"] = body
    end

    def self.display_responses(_ = nil, _ = nil, _ = nil)
      responses
    end

    # Returns all generated responses
    def self.responses
      @@responses.clone
    end

    def self.response(request)
      @@responses[request].clone
    end

    # Returns all made analytics requests
    def self.analytics_requests
      @@analytics_requests.clone
    end

    def self.config_filepath(filename)
      "#{File.dirname(File.expand_path(__FILE__))}/config/#{filename}.yml"
    end

    def self.load_endpoints(filename = nil)
      filepath = config_filepath(filename)

      admins = YAML.load_file(config_filepath('admin_endpoints'))
      application = (File.exist?(filepath) ? YAML.load_file(filepath) : [])

      admins + application
    end

    def self.reload_endpoints(_ = nil, params = {}, _ = nil)
      filename = params.fetch(:file, nil)
      @@endpoints = load_endpoints(filename).each { |endpoint| normalize_endpoint_config(endpoint) }
      @@administrative_endpoints = nil

      display_configured_endpoints.unshift "FILE --> #{filename}"
    end

    def self.display_configured_endpoints
      @@endpoints.map { |config| "#{config_method config} - #{config[:uri]} - #{config[:regex]}" }
    end

    def self.normalize_endpoint_config(endpoint)
      endpoint[:regex] = Regexp.new("^#{endpoint[:uri]}\\b", Regexp::IGNORECASE) unless endpoint[:uri].nil?
      endpoint[:verb] = endpoint[:verb].upcase unless endpoint[:verb].nil?

      endpoint
    end

    def self.administrative_endpoints
      @@administrative_endpoints ||=
        @@endpoints.select { |ep| ep[:administrative] }.map { |ep| "/#{ep[:uri]}" }
    end

    def self.config_method(config)
      config[:methods] || API.default_method
    end

    def self.default_method
      'GET'.freeze
    end

    def self.ignore_request?(endpoint)
      administrative_endpoints.include?(endpoint)
    end

    @@endpoints = nil
    @@administrative_endpoints = nil

    API.init
    API.reload_endpoints
  end

  class Bind
    class << self
      def host
        # TODO: This logic has to be refactored and/or moved completely to the client side

        # mix of these two:
        # http://stackoverflow.com/questions/14019287/get-the-ip-address-of-local-machine-rails
        # http://stackoverflow.com/questions/5029427/ruby-get-local-ip-nix
        ipv4_address = Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }

        # If IP address can not be resolved, then use localhost
        if ipv4_address
          # Due to iOS 'App Transport Security' feature
          # android? ? ipv4_address.ip_address : '127.0.0.1'
          '127.0.0.1'
        else
          'localhost'
        end
      end

      def port
        9292
      end

      def url
        "http://#{Bind.host}:#{Bind.port}"
      end
    end
  end

  class Boot
    @@boot = nil

    def initialize(stop_if_running)
      host = Bind.host
      port = Bind.port
      full_url = Bind.url

      if running?
        if stop_if_running
          abort("ERROR: Mock server already running at #{full_url}. Please stop it and run this again.")
        else
          puts "Mock server already running at #{full_url}."
        end
      else
        puts "About to boot up mock server at: #{full_url}"

        @bootup = BootupServerCommand.new(host, port)
        @bootup.execute

        while Kernel.loop
          break if running?
          puts 'Waiting for mock backend'
          sleep 0.5 unless defined?(MiniTest)
        end

        puts 'Mock server up and running'
      end
    end

    def running?
      HTTParty.get(Bind.url).response.code.to_i == 200
    rescue
      false
    end

    def close
      @bootup.close
      puts 'Mock server finished'
    end

    def self.boot(stop_if_running: true)
      @@boot = Boot.new(stop_if_running)
    end

    def self.exit
      @@boot.close unless @@boot.nil?
    end
  end
end
