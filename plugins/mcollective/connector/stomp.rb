require 'stomp'

module MCollective
    module Connector
        # Handles sending and receiving messages over the Stomp protocol
        #
        # This plugin supports version 1.1 or 1.1.6 and newer of the Stomp rubygem
        # the versions between those had multi threading issues.
        #
        # For all versions you can configure it as follows:
        #
        #    connector = stomp
        #    plugin.stomp.host = stomp.your.net
        #    plugin.stomp.port = 6163
        #    plugin.stomp.user = you
        #    plugin.stomp.password = secret
        #
        # All of these can be overriden per user using environment variables:
        #
        #    STOMP_SERVER, STOMP_PORT, STOMP_USER, STOMP_PASSWORD
        #
        # Version 1.1.6 onward support supplying multiple connections and it will
        # do failover between these servers, you can configure it as follows:
        #
        #     connector = stomp
        #     plugin.stomp.pool.size = 2
        #
        #     plugin.stomp.pool.host1 = stomp1.your.net
        #     plugin.stomp.pool.port1 = 6163
        #     plugin.stomp.pool.user1 = you
        #     plugin.stomp.pool.password1 = secret
        #
        #     plugin.stomp.pool.host2 = stomp2.your.net
        #     plugin.stomp.pool.port2 = 6163
        #     plugin.stomp.pool.user2 = you
        #     plugin.stomp.pool.password2 = secret
        #
        # Using this method you can supply just STOMP_USER and STOMP_PASSWORD
        # you have to supply the hostname for each pool member in the config.
        # The port will default to 6163 if not specified.
        class Stomp<Base
            attr_reader :connection

            def initialize
                @config = Config.instance

                @log = Log.instance
            end

            # Connects to the Stomp middleware
            def connect
                begin
                    host = nil
                    port = nil
                    user = nil
                    password = nil

                    # Maintain backward compat for older stomps
                    unless @config.pluginconf.include?("stomp.pool.size")
                        host = get_env_or_option("STOMP_SERVER", "stomp.host")
                        port = get_env_or_option("STOMP_PORT", "stomp.port", 6163).to_i
                        user = get_env_or_option("STOMP_USER", "stomp.user")
                        password = get_env_or_option("STOMP_PASSWORD", "stomp.password")

                        @log.debug("Connecting to #{host}:#{port}")
                        @connection = ::Stomp::Connection.new(user, password, host, port, true)
                    else
                        pools = @config.pluginconf["stomp.pool.size"].to_i
                        hosts = []

                        1.upto(pools) do |poolnum|
                            host = {}

                            host[:host] = get_option("stomp.pool.host#{poolnum}")
                            host[:port] = get_option("stomp.pool.port#{poolnum}", 6163).to_i
                            host[:login] = get_env_or_option("STOMP_USER", "stomp.pool.user#{poolnum}")
                            host[:passcode] = get_env_or_option("STOMP_PASSWORD", "stomp.pool.password#{poolnum}")

                            @log.debug("Adding #{host[:host]}:#{host[:port]} to the connection pool")
                            hosts << host
                        end

                        raise "No hosts found for the STOMP connection pool" if hosts.size == 0

                        @connection = ::Stomp::Connection.new({:hosts => hosts})
                    end
                rescue Exception => e
                    raise("Could not connect to Stomp Server: #{e}")
                end
            end

            # Receives a message from the Stomp connection
            def receive
                @log.debug("Waiting for a message from Stomp")
                msg = @connection.receive

                # STOMP puts the payload in the body variable, pass that
                # into the payload of MCollective::Request and discard all the 
                # other headers etc that stomp provides
                Request.new(msg.body)
            end

            # Sends a message to the Stomp connection
            def send(target, msg)
                @log.debug("Sending a message to Stomp target '#{target}'")
                # deal with deprecation warnings in newer stomp gems
                if @connection.respond_to?("publish")
                    @connection.publish(target, msg)
                else
                    @connection.send(target, msg)
                end
            end

            # Subscribe to a topic or queue
            def subscribe(source)
                @log.debug("Subscribing to #{source}")
                @connection.subscribe(source)
            end

            # Subscribe to a topic or queue
            def unsubscribe(source)
                @log.debug("Unsubscribing from #{source}")
                @connection.unsubscribe(source)
            end

            # Disconnects from the Stomp connection
            def disconnect
                @log.debug("Disconnecting from Stomp")
                @connection.disconnect
            end

            private
            # looks in the environment first then in the config file
            # for a specific option, accepts an optional default.
            #
            # raises an exception when it cant find a value anywhere
            def get_env_or_option(env, opt, default=nil)
                return ENV[env] if ENV.include?(env)
                return @config.pluginconf[opt] if @config.pluginconf.include?(opt)
                return default if default

                raise("No #{env} environment or plugin.#{opt} configuration option given")
            end

            # looks for a config option, accepts an optional default
            #
            # raises an exception when it cant find a value anywhere
            def get_option(opt, default=nil)
                return @config.pluginconf[opt] if @config.pluginconf.include?(opt)
                return default if default

                raise("No plugin.#{opt} configuration option given")
            end
        end
    end
end

# vi:tabstop=4:expandtab:ai
