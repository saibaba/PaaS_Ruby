require 'fileutils'
require 'socket'

require './syscall'
require './continst'

class ContainerManager
  attr_accessor :host_ip, :container_ip, :tenant_id, :base, :command_port
  
  def initialize
    yield self if block_given?
    @tenant_home = "/home/sai/platform/tenants/#{@tenant_id}"
    @pipe="#{@tenant_home}/comm_pipe.fifo"
    @link_host_name="v0-tenant-#{@tenant_id}"
    @link_cont_name="v1-tenant-#{@tenant_id}"
    @pid_file = "#{@tenant_home}/var/run/init.pid"
  end

  def init_pid

    pid = nil

    if File.exist?(@pid_file) and File.file?(@pid_file)
      input = open(@pid_file, "r")
      x = input.gets
      input.close
      x.chomp!
      pid = x.to_i
    end
    return pid

  end

  def init
   
    pid = init_pid
    raise "Container already running under pid: #{pid}" unless pid.nil?

    FileUtils.rm_f(@pipe)
    `ip link del #{@link_host_name} > /dev/null 2>&1`

    `mkfifo #{@pipe}`
    `ip link add name #{@link_host_name} type veth peer name #{@link_cont_name}`
    `ifconfig #{@link_host_name} #{@host_ip} up`
    `route add -host #{@container_ip} dev #{@link_host_name}`

    inst = ContainerInstance.new do |c|
      c.host_ip = "10.0.0.101"
      c.container_ip = "10.0.0.102"
      c.tenant_id = 1
      c.base = "/home/sai/platform/tenants"
      c.command_port = 5555
    end

    @init_pid =  Syscall.new.start_container("/home/sai/.rvm/rubies/ruby-1.9.3-p327/bin/ruby ./inst1.rb")

    puts "Moving link to init with below command ..."
    puts "ip link set #{@link_cont_name} netns #{@init_pid}"

    `ip link set #{@link_cont_name} netns #{@init_pid}`
   
    write_pid
 
  end

  def write_pid
    output = open(@pid_file, "w")
    output.puts(@init_pid)
    output.flush
    output.close
  end

  def start
    output = open(@pipe, "w+")
    output.puts "GO FOR IT!"
    output.flush
    output.close
  end

  def shutdown
    #send("SIGTERM")
    #sleep 5
    output = open(@pipe, "w+")
    output.puts "shutdown"
    output.flush
    output.close
    FileUtils.rm_f(@pid_file)
  end

  def send(cmd)
    puts "opening socket.."
    client = TCPSocket.open(@container_ip, @command_port)
    puts "sending command..."
    client.send(cmd, 0)
    answer = client.gets(nil)
    puts answer
    client.close
  end

  def kill_init
    pid = init_pid
    `kill -9 #{pid}`
  end

end

container1 = ContainerManager.new do |c|
  c.host_ip = "10.0.0.101"
  c.container_ip = "10.0.0.102"
  c.tenant_id = 1
  c.base = "/home/sai/platform/tenants"
  c.command_port = 5555
end

if ARGV.length == 0
  puts "Missing argument"
  exit
end

cmd = ARGV[0]

puts "Command: <#{cmd}>, my pid = #{Process.pid}"

if cmd == "start"
  container1.init
  sleep 3
  container1.start
elsif cmd == "start-http"
  container1.send("SHTTPD")
elsif cmd == "stop-http"
  container1.send("THTTPD")
elsif cmd == "shutdown"
  container1.shutdown
elsif cmd == "kill"
  container1.kill_init
else
  container1.send(cmd)
end
