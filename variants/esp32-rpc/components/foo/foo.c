#include <stdio.h>
#include <toit/ctoit.h>

static toit_err_t start(void* user_context, toit_process_context_t* process_context);
static toit_err_t on_message(void* user_context, int sender, int type, void* data, int length);
static toit_err_t on_removed(void* user_context);

typedef struct process_t {
  toit_process_context_t* process_context;
} process_t;

void __attribute__((constructor)) init() {
  printf("registering process\n");
  process_t* user_context = (process_t*)malloc(sizeof(process_t));
  if (!user_context) {
    printf("unable to allocate user context\n");
    return;
  }
  toit_add_external_process(user_context, "toit.io/external-test", &start);
}

static toit_err_t start(void* user_context, toit_process_context_t* process_context) {
  printf("starting process\n");
  process_t* process = (process_t*)(user_context);
  process->process_context = process_context;
  toit_process_cbs_t cbs = {
    .on_message = &on_message,
    .on_removed = &on_removed,
  };
  toit_err_t err = toit_set_callbacks(process_context, cbs);
  if (err != TOIT_ERR_SUCCESS) {
    printf("unable to set callbacks\n");
  }
  return TOIT_ERR_SUCCESS;
}

static toit_err_t on_message(void* user_context, int sender, int type, void* data, int length) {
  printf("received message in C\n");
  process_t* process = (process_t*)(user_context);
  if (toit_send_message(process->process_context, sender, type + 1, data, length, true) != TOIT_ERR_SUCCESS) {
    printf("unable to send\n");
  }
  if (length == 2 && ((char*)data)[0] == 99 && ((char*)data)[1] == 99) {
    toit_remove_process(process->process_context);
  }
  return TOIT_ERR_SUCCESS;
}

static toit_err_t on_removed(void* user_context) {
  printf("freeing user context\n");
  free(user_context);
  return TOIT_ERR_SUCCESS;
}
