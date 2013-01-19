#include "ruby.h"

typedef struct MethodInfo {
  VALUE obj;
  const char * func;
} MethodInfo, *pMethodInfo;

int start_container(void * arg);

int wait_for_children(pid_t pid, const char *label);

