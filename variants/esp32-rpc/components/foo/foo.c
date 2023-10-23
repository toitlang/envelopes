#include <stdio.h>
#include <toit/cmessaging.h>

static void on_created(void* user_context, HandlerContext* handler_context);
static void on_message(void* user_context, int sender, int type, void* data, int length);
static void on_release(void* user_context);

typedef struct Handler {
  HandlerContext* handler_context;
} Handler;

void __attribute__((constructor)) init() {
  printf("registering handler\n");
  Handler* user_context = (Handler*)malloc(sizeof(Handler));
  if (!user_context) {
    printf("unable to allocate user context\n");
    return;
  }
  toit_register_external_message_handler(user_context, 0, &on_created);
}

static void on_created(void* user_context, HandlerContext* handler_context) {
  Handler* handler = (Handler*)(user_context);
  handler->handler_context = handler_context;
  toit_set_callbacks(handler_context, &on_message, &on_release);
}

static void on_message(void* user_context, int sender, int type, void* data, int length) {
  printf("received message in C\n");
  Handler* handler = (Handler*)(user_context);
  if (!toit_send_message(handler->handler_context, sender, type + 1, data, length, true)) {
    printf("unable to send\n");
  }
  if (length == 2 && ((char*)data)[0] == 99 && ((char*)data)[1] == 99) {
    toit_release_handler(handler->handler_context);
  }
}

static void on_release(void* user_context) {
  printf("freeing user context\n");
  free(user_context);
}
