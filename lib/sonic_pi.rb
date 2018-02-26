require 'socket'
require 'rubygems'
require 'osc-ruby'
require 'securerandom'
require 'cgi'

class SonicPi
  MONITOR_COMMAND = "/monitor"
  RUN_COMMAND = "/run-code"
  STOP_COMMAND = "/stop-all-jobs"
  SERVER = 'localhost'
  PORT = 4557
  WAIT_TIME = 0.025
  GUI_ID = 'SONIC_PI_CLI'

  def run(command)
    monitor
    @server.add_method '/error' do |message|
      _, desc, trace, _ = message.to_a
      puts CGI.unescapeHTML(desc)
      puts CGI.unescapeHTML(trace)
      stop_server
    end
    send_command(RUN_COMMAND, command)
    @server_thread.join(WAIT_TIME)
    stop_server
  end

  def stop
    send_command(STOP_COMMAND)
  end

  def monitor_all
    monitor
    @server.add_method '/info' do |message|
      info = message.to_a
      puts
      puts "=> " + info[1].to_s
    end
    @server.add_method '/log/multi_message' do |message|
      args = message.to_a
      jobid, thread_name, runtime, _ = args.slice!(0..3)
      summary = {:run => jobid.to_i, :time => runtime.to_f}
      if not thread_name.empty? then
        summary[:thread] = thread_name
      end
      puts
      puts summary
      while not args.empty? do
        # Ignoring the "highlight" type.
        _, value = args.slice!(0..1)
        puts " " + value.to_s
      end
    end
    @server.add_method '/error' do |message|
      _, desc, trace, _ = message.to_a
      puts CGI.unescapeHTML(desc)
      puts CGI.unescapeHTML(trace)
    end

    begin
      @server_thread.join
    rescue Interrupt
    end
  end

  def test_connection!
    begin
      socket = UDPSocket.new
      socket.bind(nil, PORT)
      abort("ERROR: Sonic Pi is not listening on #{PORT} - is it running?")
    rescue
      # everything is good
    end
  end

  private

  class PortRevealingServer < OSC::Server
    def port
      return @socket.addr[1]
    end
  end

  def monitor
    @server = PortRevealingServer.new(0)
    @server_thread = Thread.fork do
      begin
        @server.run
      rescue => e
        puts "monitor: " + e.to_s
      end
    end
    send_command(MONITOR_COMMAND, @server.port)
  end

  def stop_server
    begin
      @server.stop
    rescue => e
      puts "stop_server: " + e.to_s
    end
    if @server_thread.alive? then
      @server_thread.kill
      @server_thread.join
    end
  end

  def client
    @client ||= OSC::Client.new(SERVER, PORT)
  end

  def send_command(call_type, command=nil)
    prepared_command = OSC::Message.new(call_type, GUI_ID, command)
    client.send(prepared_command)
  end
end
