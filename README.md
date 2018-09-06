# digital-mock-server

### Software Requirements

- **XCode (Only on MAC)**
- **Ruby**
- **Homebrew**
- **RVM**
- **Rails Server**
- **GIT And Sublime**

The easiest step by step installation is documented here: http://installrails.com

### Run Rubocop static code analysis

`bundle exec rake`

### Running mock API server as standalone

`bundle exec rackup config.ru`

This will fire up a Puma web server instance, typically on port 9292.    
Otherwise, take note of the specific port number Puma web server returns.   
 E.g. `bundle exec rackup config.ru --host 192.168.204.30 --port 9999`
you’ll no longer be able to type anything in that command line window.
Let this window run the server, and open another to continue working or CTRL + C to stop the server

If you wish to see the list of configured responses,
send a GET request at `http:/localhost:9292/status`  
This will show you all endpoints available that you can query.

You should then be able to access a specific endpoint via http.   
 E.g. `http://localhost:9292/collector/statement/mini`
 

### Request processing
When a request is received by the server, its URI is matched against the configured endpoints.  

The match is performed sequentially, and terminates at the first matching endpoint.  

This allows multiple configurations for different scenarios based on the same endpoint, as per the following example:  

Order | Path | Response
----- | ---- | -------
1 | collector/123/details | collector/success
2 | collector/456/details | collector/failure
3 | collector/(?<coll_id>.+)/details | collector/unknown

Once the server finds a matching endpoint, the list of dynamic configurations (see below) is scanned for a matching configuration.   
If one is found, the 2 configurations are merged together. 
  
##### Parameters
During a request processing, the mock server will inject values in the response where the following syntax is found: `%{value_name}`.
 
 The list of substitutions values comes from:
 1. Query string parameters (e.g. `?a=1&b=test`)
 1. Forms data
 1. Named capture groups from path matching (e.g. `collector/(?<coll_id>.+)/details`)
 1. `:params` property from a dynamic configuration
 1. `:params` property from the base configuration
 
Parameters included in the response that are not found in the `params` collection will not be replaced.
### Endpoints
Mocked API endpoints are configured via YAML files in the config folder.

`admin_endpoints.yml` contains endpoints used to interact with the mock server.
These endpoints have the `:administrative:` property set to `true`, and will not appear in the list of requests received,
nor in the list of returned responses.

Additionally, this file is loaded during server bootstrap, and is prepended to any other configuration file loaded afterward.

#### Endpoints configuration
Available properties:
- **:uri:** --> MANDATORY  
    Endpoint matching path.   
    `:uri:` is a regex, allowing to specify named capture groups (see the example value).     
    The captured values are injected in the parameters list.  
    Example: 'collector/offers/(?<offer_id>.+)/swipeInfo'

- **:response:** --> Use in alternative to **:generate_response:**   
    Relative path to response file to return.  
    The server will look for the file name as specified, then will append a `.json` extension, and finally a `.xml` extension.    
    If no file is found, the response body will be empty.   
    Example:'login/success'  
                                 
- **:generate_response:** --> Use in alternative to **:response:**      
    Function to call to generate the response   
    Example: 'MockBackend::API.bespoke'
    
- **:delay:**  
    Seconds to wait before returning the response. Useful to mock slow connections or long running requests.  
    Default: 0 --> No delay  
    Example: 2
  
- **:status:**   
    Returned HTTP status  
    Default: 200 --> Success response  
    Example: 404                                          
   
- **:methods:**        
    List of space separated HTTP methods accepted.  
    Default: 'GET'  
    Example: 'PUT DELETE'
    
- **:params:**     
    Parameters in addition to query string parameters, forms data and regex path matching.  
    Example: { "a": "2", "b": "3" }                      
    
- **:content_type:**     
    Specifies the content type format of the response.   
    Default: 'application/json'    
- **:xml_root:**     
    If content type is XML, specifies the name of the returned root element.  
    Example: 'collector'                      
    
- **:allow_dynamic_config:**   
    Endpoint behaviour can be modified with a dynamic configuration. See description of dynamic config below.    
    Default: true  
        
- **:administrative:**   
    Marks the endpoint as administrative.  
    Endpoints marked as administrative are not included in the list of application requests and responses.   
    Default: false  
    
- **:sticky:**
    Used ONLY for dynamic configurations. See description below.  
    Default: false
    

### Dynamic configurations
By calling the function `MockBackend::API.add_dynamic_configuration` (or through the endpoint `http://localhost:9292/dynamic_config`) during a test setup phase, it is possible to modify configurations at run-time.

These dynamic configurations are kept in a separate list from configured endpoints, and are merged together if the dynamic config matches the request URI.   
The `:uri:` property of a dynamic configuration can be null, matching any incoming request.   
Similarly to the basic configuration URI matching, the first matching configuration is used.   
The values coming from the dynamic configuration override the corresponding values of the base configuration.
 
Finally, when a dynamic configuration is consumed, it is removed from the list of dynamic configurations.  

##### Sticky dynamic configurations
In some scenarios it might be necessary to reconfigure a specific endpoint for a number of requests.  
In this case, a dynamic configuration is not viable (as it is reset after every call) and loading a new configuration might not be applicable.
For these cases, a dynamic configuration can specify the `sticky` parameter as true, to prevent it from being removed after use.  
The sticky configuration will be removed when the server is reset (using the `init` administrative endpoint) or when another sticky configuration is created that only specifies the SAME uri and `sticky: false`.

### Administrative endpoints
Some endpoints are dedicated to the management of the mock server itself and are defined in the `administrative_endpoints.yml` file. 
This file is loaded at server bootstrap.
 
The administrative endpoints follow:
- **status**  
Show status of server settings and configurations.  
Example: `http://localhost:9292/status`

- **init**  
Resets the server status and configuration, preserving ONLY endpoints configurations.  
Example: `http://localhost:9292/init`  

- **load_config**  
Loads a new endpoints configuration file, replacing the endpoints previously configured.  
Example: `http://localhost:9292/load_config?file=mobile_endpoints`  
**NOTE**: The `administrative_endpoints.yml` file is always loaded before the specified file. 

- **requests**  
Returns an array of the requests received by the server since the last initialization.  
Example: `http://localhost:9292/requests`  

- **responses**  
Returns an hash of all responses generated by the server indexed by the request uri, since the last initialization.  
Example: `http://localhost:9292/responses`  

- **dynamic_config**  
Allow to add dynamic configuration settings that will override the corresponding existing endpoint.  
All properties of the endpoint configuration can be specified as request parameters, following the same syntax 

- **response**
Defines a response that will be used for all following requests until rest or initialization.  
Example: `http://localhost:9292/response?status=201`  
Accepted parameters are:
    - body: a JSON string that will be returned as body of the response
    - status: the HTTP status
    - type: content type of the response
    - delay: delay of the response 

### Debugging the mock server in IntelliJ
Intellij can be configured to interactively debug the mock server.  
To do so, specify the `local_debug.rb` as the script to execute.  
This will start the mock server, and loop waiting for requests to come in.  
With this setup, it is possible to set breakpoints in the mock server code to properly debug it.