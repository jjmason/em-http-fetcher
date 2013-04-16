#!/usr/bin/env ruby
require 'eventmachine'
require 'em/pool'
require 'em-http-request'

module EventMachine
  class HttpFetcher
    class RequestPool < EM::Pool
      def initialize(host_resource_size, host_reuse_wait = 0)
        super()
        @host_reuse_wait = host_reuse_wait
        @host_resource_size = host_resource_size
        @host_queue = Hash.new {|h, k|
          q = EM::Queue.new
          host_resource_size.times { q.push nil }
          h[k] = q
        }
      end
      
      def perform(host, *a, &b)
        @host_queue[host].pop do |c|
          work = EM::Callback(*a, &b)
          super {
            rq = proc {
              if @host_reuse_wait > 0
                EM.add_timer(@host_reuse_wait) {
                  @host_queue[host].push c
                }
              else
                @host_queue[host].push c
              end
            }
            d = work.call
            d.callback(&rq)
            d.errback(&rq)
            d
          }
        end
      end
    end

    def initialize(opts = {})
      @concurrency       = opts[:concurrency]       || 40
      @host_concurrency  = opts[:host_concurrency]  || 2
      @host_request_wait = opts[:host_request_wait] || 0.3
      @request_pool      = nil
    end

    def request_pool
      @request_pool and return @request_pool
      @request_pool = RequestPool.new(@host_concurrency, @host_request_wait)
      @concurrency.times {|i| @request_pool.add i}
      @request_pool
    end

    def request(*args, &callback)
      url = args.first
      host = url.sub(%r{^(http://[^/]+).*$}, "\\1")
      request_pool.perform(host) do
        req = EM::HttpRequest.new(url).get *args[1..-1]
        req.callback do
          p [:success, url, req.response.size]
        end
        req.errback do
          p [:err, url, req.response.size]
        end
        req
      end
    end
  end
end


if __FILE__ == $0
  trap(:INT) { EM.stop }
  EM.run do
    r = EM::HttpFetcher.new
    ARGF.each { |line|
      line.chomp!
      line or next
      
      r.request line
    }
  end
end
