/// Modelo que describe una característica GATT descubierta en un dispositivo BLE.
class TripperGattCharacteristic {
  final String uuid;
  final bool canRead;
  final bool canWrite;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;

  const TripperGattCharacteristic({
    required this.uuid,
    this.canRead = false,
    this.canWrite = false,
    this.canWriteWithoutResponse = false,
    this.canNotify = false,
    this.canIndicate = false,
  });

  String get propertiesSummary {
    final props = <String>[];
    if (canRead) props.add('READ');
    if (canWrite) props.add('WRITE');
    if (canWriteWithoutResponse) props.add('WRITE_NO_RESP');
    if (canNotify) props.add('NOTIFY');
    if (canIndicate) props.add('INDICATE');
    return props.isEmpty ? 'NONE' : props.join(', ');
  }
}

/// Modelo que describe un servicio GATT descubierto en un dispositivo BLE.
class TripperGattService {
  final String uuid;
  final List<TripperGattCharacteristic> characteristics;

  const TripperGattService({
    required this.uuid,
    required this.characteristics,
  });
}
