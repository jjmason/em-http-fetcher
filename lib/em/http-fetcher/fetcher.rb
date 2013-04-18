#!/usr/bin/env ruby
require 'eventmachine'
require 'em/pool'
require 'em-http-request'
require 'uri'

module EventMachine
  class HttpFetcher
    class RequestPool
      def initialize(total_size, host_resource_size, host_reuse_wait = 0, opts = {})
        super()
        @total_size         = total_size
        @host_reuse_wait    = host_reuse_wait
        @host_resource_size = host_resource_size

        @total_queue        = EM::Queue.new
        total_size.times { @total_queue.push true }
        @host_pools         = Hash.new {|h, k|
          pool = EM::Pool.new
          def pool.add item
            super
            @removed.delete item
          end
          host_resource_size.times {
            pool.add EM::HttpRequest.new(k)
          }
          h[k] = { pool: pool, last_used: Time.now }
        }
        run
      end

      def perform(host, &b)
        @host_pools[host][:pool].perform do |conn|
          df = nil
          @total_queue.pop do |tqi|
            @host_pools[host][:last_used] = Time.now
            @host_pools[host][:pool].remove conn
            rq = proc {
              @total_queue.push tqi
              if @host_reuse_wait > 0
                EM.add_timer(@host_reuse_wait) {
                  @host_pools[host][:pool].add conn
                }
              else
                @host_pools[host][:pool].add conn
              end
            }
            work = EM::Callback(&b)
            df = work.call(conn)
            df.callback(&rq)
            df.errback(&rq)
            df
          end
          df
        end
      end

      def run
        # cleanup host pool timer
        EM.add_periodic_timer(10) do
          hrsize = @host_resource_size
          @host_pools.each do |host, info|
            info[:pool].instance_eval { @resources.size < hrsize } and next
            info[:last_used].to_i > Time.now.to_i - 5 * 60 and next
            @host_pools.delete host
          end
        end
      end
    end

    def initialize(opts = {})
      @concurrency       = opts[:concurrency]       || 40
      @host_concurrency  = opts[:host_concurrency]  || 2
      @host_request_wait = opts[:host_request_wait] || 0.3
      @request_pool      = nil
      @default_callbacks = []
      @default_errbacks  = []
      @req_opts = {}.merge(opts)
      @req_opts.delete :concurrency
      @req_opts.delete :host_concurrency
      @req_opts.delete :host_request_wait
    end

    def request_pool
      @request_pool ||= RequestPool.new(@concurrency, @host_concurrency, @host_request_wait, @req_opts)
    end

    def callback(&block)
      @default_callbacks << block
    end

    def errback(&block)
     @default_errbacks << block
    end

    def request(*args)
      if args.first.kind_of? Hash
        opts = args[0]
        uri = opts.delete(:uri)
      else
        uri = args.first
        opts = args[1].kind_of?(Hash) ? args[1] : {}
      end

      uri.kind_of?(URI) or uri = URI.parse(uri.to_s)
      opts = {
        :keepalive => true,
        :redirects => 20,
        :path => uri.path || '/',
      }.merge(opts)
      method = opts.delete(:method) || :get
      uri.query and otps[:query] = uri.query

      df = nil
      request_pool.perform("#{uri.scheme}://#{uri.host}") do |conn|
        df = req = conn.__send__(method, opts)
        @default_callbacks.each do |cb|
          req.callback(&cb)
        end
        @default_errbacks.each do |cb|
          req.errback(&cb)
        end
        req
      end
      df
    end
  end
end


if __FILE__ == $0
  trap(:INT) { EM.stop }
  EM.run do
    r = EM::HttpFetcher.new
    r.callback do |req|
      p [:success, req.last_effective_url, req.response.size]
    end
    r.errback do |req|
      p [:err, req.last_effective_url, req.response.size]
    end

    ARGF.each { |line|
      line.chomp!
      line or next
      req = r.request(line)
      if line == 'http://www.yahoo.co.jp/'
        req.callback do
          p :yahoo!
        end
      end
    }
  end
end
