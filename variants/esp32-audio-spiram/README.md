# ESP32-AUDIO-SPIRAM

A variant of the ESP32 envelope that supports SPIRAM (external memory)
and includes the full set of audio primitives.

This combines the configuration of `esp32-spiram` with packed-PCM
processing, additional audio DSP operations, and float32 complex FFT
operations. Use this variant for audio and spectral-processing applications
on ESP32 boards with SPIRAM that can accept the additional flash, RAM,
and CPU requirements.
