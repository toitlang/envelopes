# ESP32S2-CDC

A variant of the ESP32S2 envelope that uses the USB OTG peripheral's
CDC interface for the console instead of the default UART.

Use this variant on boards that expose the ESP32-S2's native USB
connection and should provide the console over USB without an external
USB-to-UART bridge.
