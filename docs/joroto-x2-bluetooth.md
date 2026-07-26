# JOROTO X2/X2PRO Bluetooth investigation

This document records the Bluetooth investigation performed against a JOROTO X2/X2PRO exercise
bike advertising as `JOROTO-BK-0401`. It covers the standard Bluetooth data, the proprietary
iConsole-like protocol, experiments performed with Kinomap and ESPHome, and the limits of what the
bike exposes wirelessly.

The practical conclusion is:

- Cadence and revolution timing are available through the standard Bluetooth Cycling Speed and
  Cadence service.
- Speed, distance, session duration and active duration can be derived reliably from those values.
- The console knows its physical `LOAD` setting, but no observed Bluetooth packet contains it.
- No standard or proprietary packet exposed usable power data. Kinomap appears to estimate power
  from RPM or speed rather than read measured power from the bike.
- Further investigation of physical load requires inspecting the sensor cable or console hardware.

## Bike and test equipment

- Bike: JOROTO X2/X2PRO
- Advertised name: `JOROTO-BK-0401`
- Observed BLE address: `C1:33:36:33:72:71`
- BLE inspection: nRF Connect on Android
- Traffic capture: Android Bluetooth HCI snoop log from a Kinomap session
- ESPHome hardware: ESP32-C6-DevKitC N4
- ESPHome framework: ESP-IDF

The user manual provides two useful clues:

- The console displays both `WATT` and `LOAD`, with load represented from 1 to 100.
- The monitor is described as using the "Iconsole protocol".

The manual also shows a sensor cable between the bike and monitor. That is the likely boundary to
inspect if physical load is revisited with additional hardware.

## Connection and pairing behaviour

The bike is a BLE GATT server. A phone, ESP32 or fitness app acts as the GATT client.

It does **not** need to be paired or bonded at the Android operating-system level. Android's normal
Bluetooth pairing UI produced an "incorrect PIN" failure even though no PIN was entered. This is
consistent with a BLE peripheral intended for direct, unbonded GATT connections rather than normal
OS pairing.

nRF Connect successfully connected while displaying `CONNECTED` and `NOT BONDED`. Its local GATT
server feature was not required; only the client view was used.

The bike should be awake and no fitness app should be connected while another client is testing it.
In practice, assume it supports only one useful client connection at a time.

## Observed GATT database

| Service | Characteristic | Properties | Observed purpose |
| --- | --- | --- | --- |
| `0x1800` Generic Access | Standard characteristics | Standard | Device identity and connection data |
| `0x1801` Generic Attribute | Standard characteristics | Standard | GATT service management |
| `0x1816` Cycling Speed and Cadence | `0x2A5B` CSC Measurement | Notify | Wheel/crank counters and event times |
| `0x1816` Cycling Speed and Cadence | `0x2A5C` CSC Feature | Read | Wheel, crank and multiple locations supported |
| `0x1816` Cycling Speed and Cadence | `0x2A5D` Sensor Location | Read | Reported as `Right Crank` |
| `0x1816` Cycling Speed and Cadence | `0x2A55` SC Control Point | Write, Indicate | Standard CSC control point |
| `0x180A` Device Information | Standard characteristics | Read | Device information |
| `0xFFF0` Proprietary | `0xFFF1` | Notify | Proprietary acknowledgements and telemetry |
| `0xFFF0` Proprietary | `0xFFF2` | Write, Write Without Response | Proprietary client commands |
| `02f00000-0000-0000-0000-00000000fe00` | Not investigated | Unknown | Additional vendor-specific service |

The bike did not expose the standard Cycling Power service (`0x1818`) or Fitness Machine service
(`0x1826`). The standard CSC service is therefore the only confirmed source of useful workout data.

See the Bluetooth SIG's [Cycling Speed and Cadence Service specification][bluetooth-csc] and
[Assigned Numbers][bluetooth-assigned-numbers] for the standard fields and UUIDs.

## Standard CSC measurements

The CSC Measurement characteristic is a standard notification. Its flags indicate whether wheel
data, crank data, or both are present. The bike reports cumulative revolution counters and event
times rather than directly reporting RPM.

For crank data:

```text
cadence_rpm = revolution_delta * 60 * 1024 / crank_event_time_delta
```

The crank event-time counter is a wrapping 16-bit counter measured in 1/1024-second units. Counter
deltas must therefore use unsigned 16-bit arithmetic.

The current ESPHome integration derives speed and distance using a virtual wheel model:

```text
virtual wheel revolutions per crank = 3.0
virtual wheel circumference         = 1.50 m
speed_kmh = cadence_rpm * 3.0 * 1.50 * 60 / 1000
```

This produces approximately 16.2 km/h at 60 RPM, close to the speed Kinomap displayed during the
tests. It is a calibration rather than a physical wheel measurement.

When pedalling stops, the counters no longer provide a new movement interval from which to compute
zero RPM. A client must apply its own timeout. The production ESPHome configuration sets live
cadence and speed to zero after five seconds without a crank movement. The first sample after a long
pause is used only as a new baseline, preventing the wrapping event timer from producing a bogus
cadence or active-time spike.

## Proprietary service discovery

Subscribing to `FFF1` notifications alone did not produce the full proprietary stream. Kinomap sent
commands to `FFF2` to initialise and poll it. The useful exchange was recovered from an Android HCI
snoop capture rather than inferred from the UI.

The relevant ATT handles in that capture were:

- `0x0010`: `FFF1` notification value
- `0x0011`: `FFF1` Client Characteristic Configuration descriptor
- `0x0013`: `FFF2` write value

Kinomap first enabled `FFF1` notifications by writing `01 00` to the CCCD at handle `0x0011`.

It then wrote the following packets to `FFF2`:

```text
F0 A0 00 00 90
F0 A0 00 C8 58
F0 A2 00 C8 5A  # repeated approximately once per second
```

The capture contained 99 repeated `A2` poll requests. The bike acknowledged initialisation with:

```text
F0 B0 00 C8 68
```

It responded to the poll with a compact 19-byte `B2` packet such as:

```text
F0 B2 00 C8 00 00 00 00 00 3C 00 00 00 00 00 00 00 00 A6
```

The final byte is a checksum calculated as the sum of every preceding byte modulo 256.

## Compact JOROTO `B2` packet

The observed 19-byte packet is:

| Offset | Meaning | Observation |
| ---: | --- | --- |
| 0 | Header | Always `F0` |
| 1 | Response type | Always `B2` for telemetry |
| 2 | Protocol field | Always `00` in observed telemetry |
| 3 | Protocol field | Always `C8` in observed telemetry |
| 4-8 | Unknown/reserved | Zero during the controlled tests |
| 9 | Cadence | RPM as a direct integer value |
| 10-17 | Unknown/reserved | Zero during the controlled tests |
| 18 | Checksum | Sum of bytes 0-17 modulo 256 |

Offset 9 ranged through plausible RPM values while pedalling, dropped to zero when stopped, and
agreed with the standard CSC-derived cadence. The checksum at offset 18 changed correspondingly.

No other telemetry byte changed when the physical resistance knob was moved from minimum to
maximum while cadence was held as consistently as practical. In particular, offsets 16 and 17,
where standard iConsole packets usually carry power, remained zero.

Some short acknowledgement packets temporarily populated the generic `Unknown Value N` sensors
during development. Those values must not be confused with fields in a 19-byte `B2` telemetry
packet; the raw packet type and length must be checked first.

## Comparison with standard iConsole

Two open-source iConsole implementations were examined:

- Harald Hoyer's [original reverse-engineering implementation][hoyer-iconsole]
- Christopher Smith's [current `iconsole-plus` codec][iconsole-plus-codec]

Those implementations expect a 21-byte `B2` telemetry packet:

| Offsets | Standard iConsole field |
| ---: | --- |
| 2-5 | Duration |
| 6-7 | Speed, tenths of km/h |
| 8-9 | Cadence/RPM |
| 10-11 | Distance |
| 12-13 | Calories |
| 14-15 | Heart rate |
| 16-17 | Power, tenths of a watt |
| 18 | Resistance/load level |
| 19 | Running state |
| 20 | Checksum |

The standard variant encodes many numeric pairs with a `+1` offset, decoded approximately as:

```text
value = (high_byte - 1) * 100 + (low_byte - 1)
```

The JOROTO response is not merely a truncated standard packet. Its byte 18 is already the checksum,
so the standard load, running-state and checksum positions do not exist. Its RPM byte also uses a
different compact representation.

## Standard command experiment

An opt-in ESPHome experiment sent the standard iConsole handshake while preserving every response.
No resistance-control command was sent.

The following responses were observed:

| Request | Purpose in reference implementations | JOROTO response |
| --- | --- | --- |
| `F0 A0 01 01 92` | Standard ping | `F0 B0 00 C8 68` |
| `F0 A1 01 01 93` | Status | `F0 B1 00 C8 07 50 C0` |
| `F0 A3 01 01 01 96` | Protocol initialisation | No distinct `B3` response observed |
| 15-byte `A4` packet | Protocol/workout initialisation | `F0 B4 00 C8 00 6C` |
| `F0 A5 01 01 02 99` | Start workout | `F0 B5 00 C8 01 6E` |
| `F0 A2 01 01 94` | Standard telemetry poll | Still returned the compact 19-byte `B2` packet |

The `B1` status response was sampled more than once and remained identical while the bike was used.
The standard handshake was therefore accepted at least partially, but it did not unlock the
standard 21-byte telemetry format.

`A6` was deliberately not tested. In the reference protocol it sets electronic resistance on
motor-controlled equipment; it does not query a manual resistance knob. The JOROTO's physical knob
cannot be controlled by this command, and an acknowledgement would only reflect a requested target,
not measured resistance.

The experiment is retained in Git history for reference:

- `5c86964` - reproduce Kinomap initialisation and compact polling
- `805d8e0` - probe the standard iConsole handshake and 21-byte parser

These commits are not intended for the production configuration.

## Power and load findings

The console visibly knows the physical load setting, but the following evidence indicates that it
is not transmitted over Bluetooth:

1. The standard CSC service contains no power or resistance fields.
2. No Cycling Power or Fitness Machine service is exposed.
3. Every byte of the proprietary `B2` packet was recorded.
4. Only RPM and its checksum changed while physical load was varied.
5. The usual iConsole power bytes remained zero.
6. Standard iConsole commands did not unlock a longer packet.
7. The status response did not change with use.

Kinomap displayed a wattage value, but a controlled test at roughly 60 RPM while moving from minimum
to maximum resistance did not produce a corresponding wattage change. The most likely explanation
is that Kinomap estimates watts from RPM or its derived speed using a fixed model. This is an
inference; the Kinomap calculation itself was not available for inspection.

## ESP32-C6 connection issue and fix

Initial ESPHome attempts repeatedly failed to connect with BLE status 133 and controller
`Command Disallowed` errors. The problem was a scan-to-connect race on the ESP32-C6 rather than
pairing, encryption or another connected client.

The stable tracker configuration is:

```yaml
esp32_ble_tracker:
  scan_parameters:
    interval: 1100ms
    window: 300ms
    active: false
```

Passive scanning and an idle gap between scan windows allow the controller to stop scanning before
opening the client connection. A full-width 1100 ms scan window was unreliable.

## Production ESPHome behaviour

The production configuration in [`esp32-joroto-bike.yaml`](../esp32-joroto-bike.yaml) uses the
standard CSC service for:

- Cadence
- Calibrated virtual speed
- Accumulated distance
- Crank revolutions
- Session duration
- Actual active duration
- Pedalling state
- Configurable inactivity reset

The proprietary characteristic and byte sensors remain available for diagnostics, but production
firmware does not send the Kinomap initialisation/polling sequence. They will therefore normally
remain unknown unless another client has activated the stream.

## What further investigation would require

Bluetooth-only investigation is considered exhausted. A meaningful next step requires additional
hardware and physical access:

1. Inspect the monitor's sensor connector and wiring.
2. Measure each line with a multimeter while changing load.
3. Use an oscilloscope or logic analyser if a line carries pulses or serial data.
4. If load is an analogue voltage, buffer or divide it appropriately before connecting it to an ESP
   ADC. Do not connect an unknown console signal directly to a 3.3 V ESP input.
5. If it is digital, identify voltage levels and protocol before attaching an ESP GPIO.

This may expose the console's internal load-position signal, but it changes the project from a
software-only BLE integration into a hardware modification.

## Repeating the BLE inspection

With nRF Connect:

1. Wake the bike by pedalling.
2. Connect directly as a GATT client; do not use Android's pairing screen.
3. Open service `0x1816` and enable notifications on `0x2A5B` for standard CSC data.
4. Open service `0xFFF0` and enable notifications on `0xFFF1` for proprietary responses.
5. Write only known packets to `0xFFF2`, keeping a raw log of every response.

For app traffic, enable Android's Bluetooth HCI snoop log, reproduce a short session, generate a bug
report, and inspect ATT writes and notifications in Wireshark. Bug reports contain unrelated private
device data and should not be committed to this repository.

[bluetooth-assigned-numbers]: https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html
[bluetooth-csc]: https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html
[hoyer-iconsole]: https://git.hoyer.xyz/harald/iconsole/src/branch/master/iConsole.py
[iconsole-plus-codec]: https://github.com/christopher-david-smith/iconsole-plus/blob/main/src/iconsole_plus/codec.py
