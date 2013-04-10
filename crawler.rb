#!/usr/bin/env ruby
require 'eventmachine'
require 'em-http-request'
require 'monitor'

class RssFetcher
  class CategolizedPool < EM::Pool
    def initialize(category_resource_size, category_reuse_wait = 0)
      super()
      @category_reuse_wait = category_reuse_wait
      @category_resource_size = category_resource_size
      @category_queue = Hash.new {|h, k|
        q = EM::Queue.new
        category_resource_size.times { q.push nil }
        h[k] = q
      }
    end
    
    def perform(category, *a, &b)
      @category_queue[category].pop do |c|
        work = EM::Callback(*a, &b)
        super {
          rq = proc {
            if @category_reuse_wait > 0
              EM.add_timer(@category_reuse_wait) {
                @category_queue[category].push c
              }
            else
              @category_queue[category].push c
            end
          }
          work.call.callback(&rq).errback(&rq)
        }
      end
    end
  end

  def initialize
    @concurrency      = 40
    @host_concurrency = 2
    @request_pool     = CategolizedPool.new(@host_concurrency, 0.3)
    @concurrency.times {|i| @request_pool.add i}
  end

  def request(*args)
    url = args.first
    host = url.sub(%r{^(http://[^/]+).*$}, "\\1")
    @request_pool.perform(host) do
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


if __FILE__ == $0
  trap(:INT) { EM.stop }
  EM.run do
    r = RssFetcher.new
    ARGF.each { |line|
      line.chomp!
      line or next
      
      r.request line
    }
  end
end
