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

    @init_pid =  Syscall.new.start_container("/home/sai/.rvm/rubies/ruby-1.9.3-p327/bin/ruby ./continst.rb #{@tenant_id}")

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
    puts "opening socket to host #{@container_ip}:#{@command_port} .."
    client = TCPSocket.open(@container_ip, @command_port)
    puts "sending command..."
    client.send(cmd, 0)
    puts "waiting for response ..."
    answer = client.gets(nil)
    puts answer
    client.close
  end

  def kill_init
    pid = init_pid
    `kill -9 #{pid}`
  end

end

def load_conf(tenant_id)
  return Hash[*File.read("/home/sai/platform/tenants/#{tenant_id}/etc/container/container.conf").split(/[= \n]+/)]
end


if ARGV.length != 2
  puts "Missing argument: usage ruby contmgr.rb tenant_id cmd"
  exit
end

tenant_id = ARGV[0]
cmd = ARGV[1]

puts "Tenant: <#{tenant_id}> Command: <#{cmd}>, my pid = #{Process.pid}"

cfg = load_conf(tenant_id)

container1 = ContainerManager.new do |c|
  c.host_ip = cfg['host_ip']
  c.container_ip = cfg['container_ip']
  c.tenant_id = tenant_id.to_i
  c.base = "/home/sai/platform/tenants"
  c.command_port = cfg['command_port'].to_i
end

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
