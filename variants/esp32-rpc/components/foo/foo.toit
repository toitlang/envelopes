
import expect
import monitor

TYPE ::= 100  // Don't overlap with system messages.
EXTERNAL_PID ::= pid-for-external-id_ "toit.io/external-test"

main:
  print "starting"
  handler := MessageHandler
  set_system_message_handler_ (TYPE + 1) handler
  expect.expect (Process.current.id != EXTERNAL_PID)

  test handler #[1]
  test handler #[1, 2, 3, 4]
  test handler #[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  test handler (ByteArray 3: it)
  test handler (ByteArray 319: it)
  test handler (ByteArray 3197: it)
  test handler (ByteArray 31971: it)
  test handler #[99, 99]

test handler/MessageHandler data/ByteArray:
  copy := data.copy  // Data can be neutered as part of the transfer.
  process_send_ EXTERNAL_PID TYPE data
  print "receiving"
  result := handler.receive
  print "received $result.size"
  expect.expect_bytes_equal copy result

class MessageHandler implements SystemMessageHandler_:
  messages_ ::= monitor.Channel 1

  on_message type/int gid/int pid/int argument -> none:
    expect.expect_equals EXTERNAL_PID pid
    expect.expect_equals (TYPE + 1) type
    messages_.send argument

  receive -> any:
    return messages_.receive
