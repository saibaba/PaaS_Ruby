#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/prctl.h>
#include <unistd.h>
#include <sched.h>

#include "container.h"

#include "ruby.h"

// TODO why do I need this?
int pivot_root(const char *, const char *);

static ID id_push;

static VALUE m_init(VALUE self)
{
  return self;
}

static void set_process_name(const char *myProcessName)
{
  prctl(PR_SET_NAME, (unsigned long)myProcessName, 0,0,0);
}

static VALUE m_pivot_root(VALUE self, VALUE new_root, VALUE old_root)
{
  const char *p = StringValueCStr(new_root);
  const char *o = StringValueCStr(old_root);
  int rv = pivot_root(p, o);
  printf("new_root=%s\nold_root=%s\nrv=%d\n", p, o, rv);
  return INT2NUM(rv);
}

static VALUE m_chroot(VALUE self, VALUE new_root)
{
  char *p = StringValueCStr(new_root);
  int rv = chroot(p);
  printf("chroot rv=%d\n", rv);
  return INT2NUM(rv);
}

static void invoke(const char * command)
{

  pid_t cpid = fork();
  if (cpid == 0)  {
    const char *myProcessName = "init-runner for container 1";
    set_process_name(myProcessName);
    fprintf(stderr, "init-runner started... doing system...\n");
    system(command);

  } else {
    wait_for_children(cpid, "init-runner" ); 
    fprintf(stderr, "wait for init-runner is over");
  }
}

static int invoke_wrapper(void * arg)
{
  const char *myProcessName = "init for container 1";
  const char *command = (const char *) arg;
  set_process_name(myProcessName);
  
  invoke(command);
  return 0;
}

static VALUE m_start_container(VALUE self, VALUE command)
{
  void *childstack;
  int stacksize = getpagesize() * 4;
  void *stack = malloc(stacksize);
  if (!stack) {
    perror("malloc");
    return INT2NUM(-1);
  }
  childstack = stack + stacksize;

  const char *cmdstr = StringValueCStr(command);
  int flags = CLONE_NEWNET| CLONE_NEWNS| CLONE_NEWPID;
  pid_t cpid =  clone(invoke_wrapper, childstack, flags, (void *) cmdstr); 
  fprintf(stderr, "PID of init from outside: %d\n", cpid);
  return INT2NUM(cpid);
}

VALUE cSyscall;

void Init_syscall() {

  cSyscall = rb_define_class("Syscall", rb_cObject);
  rb_define_method(cSyscall, "initialize", m_init, 0);
  rb_define_method(cSyscall, "pivot_root", m_pivot_root, 2);
  rb_define_method(cSyscall, "chroot", m_chroot, 1);
  rb_define_method(cSyscall, "start_container", m_start_container, 1);
  id_push = rb_intern("push");
}
