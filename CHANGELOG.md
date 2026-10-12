## 0.0.1

* Initial release.
* `UhfReader`: connect/disconnect, continuous tag inventory, RF power, battery,
  and a confirmation buzzer.
* `RFIDTag` model (EPC, RSSI, timestamp).
* `tagStream`, `statusStream`, and `triggerStream` for reactive use.
* Physical scan-trigger support via `FlutterUhfRfidPlugin.dispatchTrigger`.
* Android only; built on the `com.rfid.trans` vendor SDK.
