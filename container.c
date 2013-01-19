#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sched.h>
#include "container.h"

int wait_for_children(pid_t pid, const char *label)
{

  pid_t w;
  int status;
  fprintf(stderr, "wait_for_children: %s\n", label);

  do {
    w = waitpid(pid, &status, WUNTRACED | WCONTINUED);
    if (w == -1) {
      perror("waitpid");
      exit(EXIT_FAILURE);
    }

    if (WIFEXITED(status)) {
      printf("exited, status=%d\n", WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
      printf("killed by signal %d\n", WTERMSIG(status));
    } else if (WIFSTOPPED(status)) {
      printf("stopped by signal %d\n", WSTOPSIG(status));
    } else if (WIFCONTINUED(status)) {
      printf("continued\n");
    }
  } while (!WIFEXITED(status) && !WIFSIGNALED(status));

  return status;
}

void wait_for_ok(char * path)
{
  FILE *fp  = fopen(path, "r");
  char readbuf[80];
  fgets(readbuf, 80, fp);
  fclose(fp);
  fprintf(stderr, readbuf); 
}

void wait_for_shutdown(char * path)
{
  FILE *fp  = fopen(path, "r");
  char readbuf[80];
  fgets(readbuf, 80, fp);
  fprintf(stderr, "got termination req: %s\n", readbuf);
  fclose(fp);
  fprintf(stderr, readbuf);
}

int run(pMethodInfo mi)
{
  return rb_funcall(mi->obj, rb_intern(mi->func), 0, NULL);
}

int start_container(void * arg)
{
  pMethodInfo mi = (pMethodInfo) arg;
  printf("In the CONTAINER, my pid is: %d (must be 1, is it?)\n", getpid());
  run(mi);
  return (0);
}
