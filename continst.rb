require 'fileutils'
require 'socket'

class ContainerInstance

  attr_accessor :host_ip, :container_ip, :tenant_id, :base, :command_port
  
  def initialize

    puts "ContainerInstance, my pid = #{Process.pid}"

    @base = "/home/sai/platform/tenants"

    yield self if block_given?
    @tenant_home = "#{@base}/#{@tenant_id}"
    @pipe="#{@tenant_home}/comm_pipe.fifo"
    @link_host_name="v0-tenant-#{@tenant_id}"
    @link_cont_name="v1-tenant-#{@tenant_id}"
  end

  def runcmd(cmd)
    pid = Process.fork {
      $0 = "ruby continst-#{@tenant_id}:runcmd:#{cmd}"
      Process.setsid
      STDIN.reopen '/dev/null'
      STDOUT.reopen '/dev/null', 'a'
      STDERR.reopen STDOUT
      `#{cmd}`
    }
    
    Process.waitpid(pid)

  end

  def init

    puts "CONTINST: Copying resolv.conf..."
    puts "cp /etc/resolv.conf #{@tenant_home}/etc"
    runcmd("cp /etc/resolv.conf #{@tenant_home}/etc")


    puts "LCONTINST: mouting..."
    `mount -n -t proc none #{@tenant_home}/proc`
    `mount --make-private -n --bind #{@tenant_home}/proc /proc`
    `mount --make-private -n --bind #{@tenant_home}/tmp /tmp`
    `mount --make-private -n --bind #{@tenant_home}/etc /etc`
    `mount --make-private -n --bind #{@tenant_home}/var /var`

    puts "LCONTINST: ifconfig..."
    `ifconfig #{@link_cont_name} #{@container_ip} up`
    puts "LCONTINST: route..."
    `route add default gw #{@host_ip} #{@link_cont_name}`
    puts "LCONTINST: lo..."
    `ifconfig lo up`


    puts "LCONTINST: Launching listener..."

    @listener_pid = Process.fork {
      $0 = "ruby continst-#{@tenant_id}:listener"
      require './listener'
      listener_main
    }

    puts 'starting sshd'
    @sshd_pid = Process.fork {
      puts 'starting sshd instance'
      `/usr/sbin/sshd`
    }

  end

  def term
    puts "kill #{@listener_pid}"
    `kill #{@listener_pid}`
    puts "ifconfig #{@link_cont_name} #{@container_ip} down"
    `ifconfig #{@link_cont_name} #{@container_ip} down`
    puts "ip link del #{@link_cont_name}"
    `ip link del #{@link_cont_name}`
    puts 'unmounting iproc tmp etc var...'
    `umount /proc`
    `umount /tmp`
    `umount /etc`
    `umount /var`
  end

  def wait_for_ok

    puts "CONTINST: Waiting for ok..."
    pipe = open(@pipe, "r")
    l = pipe.gets
    pipe.close
    puts "Line received: #{l}"
  end

  def wait_for_shutdown

    pipe = open(@pipe, "r")
    l = pipe.gets 
    pipe.close
    puts "Got termination request: #{l}"
  end

  def run
    puts "An instance of container being launched for tenant: #{@tenant_id}"
    wait_for_ok
    init
    wait_for_shutdown
    term
  end

end
