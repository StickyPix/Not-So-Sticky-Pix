// lib/services/ble_image_client.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleImageClient {
  // ==== MUST MATCH FIRMWARE ====
  // These UUIDs match exactly with your main.c firmware
  static final Guid svcUuid = Guid('12345678-1234-5678-1234-56789abcdef0');
  static final Guid sizeUuid = Guid('12345678-1234-5678-1234-56789abcdef1');
  static final Guid dataUuid = Guid('12345678-1234-5678-1234-56789abcdef2');
  static final Guid progUuid = Guid('12345678-1234-5678-1234-56789abcdef3');
  static final Guid unpairUuid = Guid('12345678-1234-5678-1234-56789abcdef4');
  static final Guid customBatteryLevelUuid = Guid(
    '12345678-1234-5678-1234-56789abcdef4',
  );
  static final Guid deviceIdUuid = Guid('12345678-1234-5678-1234-56789abcdef9');

  // Standard Battery Service
  static final Guid batterySvcUuid = Guid('180F');
  static final Guid batteryLevelUuid = Guid('2A19');

  static const Duration scanDuration = Duration(seconds: 8);
  static const int preferredMtu = 247;
  static const int maxChunkHint = 244;
  static const int chunksPerYield = 8;
  static const Duration writeGap = Duration(milliseconds: 2);

  /// Open scan (no service filter) -> most compatible
  static Future<List<ScanResult>> scanOpen({Duration? timeout}) async {
    // Ensure Bluetooth is ready before scanning
    await waitForBluetoothEnabled();

    final t = timeout ?? scanDuration;
    final List<ScanResult> found = [];

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }

    await FlutterBluePlus.startScan(
      timeout: t,
      withServices: const <Guid>[], // IMPORTANT: empty list, not null
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final i = found.indexWhere(
          (e) => e.device.remoteId == r.device.remoteId,
        );
        if (i < 0) {
          found.add(r);
        } else if (r.rssi > found[i].rssi) {
          found[i] = r;
        }
      }
    });

    await Future.delayed(t);

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await sub.cancel();

    found.sort((a, b) => b.rssi.compareTo(a.rssi));
    return found;
  }

  static Future<void> sendImage({
    required BluetoothDevice device,
    required Uint8List image,
    void Function(int percent)? onProgress,
    void Function(int level)? onBatteryLevel,
  }) async {
    StreamSubscription<List<int>>? progSub;
    BluetoothCharacteristic? progChar;
    bool transferComplete = false;

    try {
      // Connect with explicit timeout and error handling
      print("Connecting to device: ${device.remoteId}");
      await device.connect(autoConnect: false);
      print("Connected to device: ${device.remoteId}");

      // Wait for connection to stabilize
      print("Waiting for connection to stabilize...");
      await Future.delayed(Duration(milliseconds: 500));

      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
        print("Requested high connection priority");
      } catch (e) {
        print("Connection priority request skipped: $e");
      }

      try {
        final mtu = await device.requestMtu(preferredMtu);
        print("Requested MTU $preferredMtu, negotiated MTU: $mtu");
      } catch (e) {
        print("MTU request skipped: $e");
      }

      // Discover services
      print("Discovering services...");
      final services = await device.discoverServices();
      final imgService = services.firstWhere(
        (s) => s.uuid == svcUuid,
        orElse: () => throw Exception('Custom Image Service not found'),
      );
      print(
        "Found image service with ${imgService.characteristics.length} characteristics",
      );

      final sizeChar = _findChar(imgService, sizeUuid);
      final dataChar = _findChar(imgService, dataUuid);
      progChar = _findCharOrNull(imgService, progUuid);

      print("Size char: ${sizeChar.uuid}");
      print("Data char: ${dataChar.uuid}");
      print("Prog char: ${progChar?.uuid}");

      // Try to read Battery Level
      try {
        final level = await _readBatteryLevelFromServices(services, imgService);
        print("Battery Level: $level%");
        onBatteryLevel?.call(level);
      } catch (e) {
        print("Battery read failed (ignoring): $e");
      }

      // Subscribe to progress notifications (optional)
      if (progChar != null) {
        try {
          await progChar.setNotifyValue(true);
          progSub = progChar.onValueReceived.listen((v) {
            if (v.isNotEmpty) {
              final pct = v.first.clamp(0, 100);
              print("Firmware progress: $pct%");
              onProgress?.call(pct);

              // Check if transfer is complete (firmware reached 100%)
              if (pct == 100) {
                transferComplete = true;
                print("Firmware reports transfer complete!");
              }
            }
          });
          print("Progress notifications enabled");
        } catch (e) {
          print("Progress notifications failed: $e");
        }
      }

      // ATT payload is MTU - 3. Keep a hard cap so firmware buffers stay sane.
      final negotiatedMtu = device.mtuNow;
      final maxPayload = math.max(20, negotiatedMtu - 3);
      final payload = math.min(maxChunkHint, maxPayload);
      print(
        "Using MTU: $negotiatedMtu; payload per chunk: $payload "
        "(max payload: $maxPayload)",
      );
      print("Total chunks needed: ${(image.length / payload).ceil()}");

      // 1) Write image size (4 bytes little-endian) to TEXT_SIZE characteristic
      print("Writing image size: ${image.length} bytes");
      final sizeLe = ByteData(4)..setUint32(0, image.length, Endian.little);
      final sizeBytes = sizeLe.buffer.asUint8List();
      print(
        "Size bytes: ${sizeBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
      );

      // Log first 32 bytes of the image data for comparison
      print(
        "First 32 bytes of image data: ${image.take(32).map((b) => '${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
      );

      await sizeChar.write(sizeBytes, withoutResponse: false);
      print("Size written successfully");

      // 2) Chunk write image data to TEXT_DATA characteristic.
      print(
        "Data characteristic properties: write=${dataChar.properties.write}, writeWithoutResponse=${dataChar.properties.writeWithoutResponse}, notify=${dataChar.properties.notify}",
      );

      final useWriteWithoutResponse = dataChar.properties.writeWithoutResponse;
      if (!useWriteWithoutResponse && !dataChar.properties.write) {
        throw Exception(
          'TEXT_DATA characteristic does not support write operations',
        );
      }

      // Additional safety: verify characteristic is part of GATT service
      if (dataChar.serviceUuid != svcUuid) {
        throw Exception(
          'TEXT_DATA characteristic is not part of the expected GATT service',
        );
      }

      print(
        "Using ${useWriteWithoutResponse ? 'write-without-response' : 'write-with-response'}: "
        "$payload bytes per chunk, yielding every $chunksPerYield chunks",
      );

      int sent = 0;
      int chunkCount = 0;

      while (sent < image.length) {
        final end = math.min(sent + payload, image.length);
        final chunk = image.sublist(sent, end);
        chunkCount++;

        print(
          "Sending chunk $chunkCount: bytes ${sent}-${end - 1} (${chunk.length} bytes)",
        );

        // Log first few bytes of chunk for debugging
        if (chunkCount <= 3 || chunkCount % 10 == 0) {
          final previewBytes = chunk
              .take(4)
              .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
              .join(' ');
          print("  Chunk $chunkCount preview: $previewBytes...");
        }

        try {
          await dataChar.write(chunk, withoutResponse: useWriteWithoutResponse);
          sent = end;

          // Calculate and report progress locally
          final pct = ((sent * 100) / image.length).floor().clamp(0, 100);
          print("Local progress: $pct% ($sent/${image.length} bytes)");
          onProgress?.call(pct);
        } catch (e) {
          print("ERROR: Failed to write chunk $chunkCount: $e");
          print("Retrying chunk $chunkCount...");

          // Retry once with response enabled. This is slower, but gives the
          // stack a clean acknowledged retry path if the fast queue overflows.
          await Future.delayed(Duration(milliseconds: 100));
          try {
            await dataChar.write(chunk, withoutResponse: false);
            sent = end;
            print("Retry successful for chunk $chunkCount");
          } catch (e2) {
            print("ERROR: Retry failed for chunk $chunkCount: $e2");
            throw Exception(
              'Failed to send chunk $chunkCount after retry: $e2',
            );
          }
        }

        if (useWriteWithoutResponse && chunkCount % chunksPerYield == 0) {
          await Future.delayed(writeGap);
        }
      }

      print("All chunks sent successfully!");
      print("Total chunks sent: $chunkCount");
      print("Total bytes sent: $sent");
      print(
        "Transfer summary: ${image.length} bytes sent in $chunkCount chunks via GATT characteristics",
      );

      // Wait for firmware to complete processing
      print("Waiting for firmware to complete processing...");

      // Wait up to 10 seconds for firmware to reach 100%
      int waitTime = 0;
      while (!transferComplete && waitTime < 10000) {
        await Future.delayed(Duration(milliseconds: 100));
        waitTime += 100;
        if (waitTime % 1000 == 0) {
          print("Still waiting... (${waitTime / 1000}s)");
        }
      }

      if (transferComplete) {
        print("Transfer completed successfully! Firmware confirmed 100%");
      } else {
        print("Warning: Firmware did not reach 100% within 10 seconds");
        print("But all data was sent successfully");
      }

      // Additional safety delay
      print("Final safety delay...");
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      print("ERROR in sendImage: $e");
      rethrow;
    } finally {
      try {
        await progSub?.cancel();
        print("Progress subscription cancelled");
      } catch (e) {
        print("Error cancelling progress: $e");
      }
      try {
        await device.disconnect();
        print("Device disconnected");
      } catch (e) {
        print("Error disconnecting: $e");
      }
    }
  }

  /// Read device ID from the DEVICE_ID characteristic
  static Future<String?> readDeviceId(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);

      final services = await device.discoverServices();
      final imgService = services.firstWhere(
        (s) => s.uuid == svcUuid,
        orElse: () => throw Exception('Custom Image Service not found'),
      );

      final deviceIdChar = _findCharOrNull(imgService, deviceIdUuid);
      if (deviceIdChar == null) return null;

      final value = await deviceIdChar.read();
      return String.fromCharCodes(value);
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  /// Read battery level from the standard Battery Service (180F / 2A19).
  static Future<int> readBatteryLevel(BluetoothDevice device) async {
    try {
      await waitForBluetoothEnabled();
      await device.connect(autoConnect: false);

      final services = await device.discoverServices();
      BluetoothService? imgService;
      for (final service in services) {
        if (service.uuid == svcUuid) {
          imgService = service;
          break;
        }
      }
      return await _readBatteryLevelFromServices(services, imgService);
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  /// Trigger unpair on the device
  static Future<void> unpairDevice(BluetoothDevice device) async {
    try {
      await waitForBluetoothEnabled();
      await device.connect(autoConnect: false);

      final services = await device.discoverServices();
      final imgService = services.firstWhere(
        (s) => s.uuid == svcUuid,
        orElse: () => throw Exception('Custom Image Service not found'),
      );

      final unpairChar = _findChar(imgService, unpairUuid);
      print("Found UNPAIR characteristic: ${unpairChar.uuid}");

      // Write dummy byte to trigger unpair
      await unpairChar.write([0x01], withoutResponse: false);
      print("Unpair command sent successfully");
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  /// Simple test: Send just a text size value to TEXT_SIZE characteristic
  static Future<bool> testSimpleTextSize(
    BluetoothDevice device,
    int testSize,
  ) async {
    try {
      print("=== SIMPLE TEXT_SIZE TEST ===");
      print("Test size: $testSize bytes");

      await device.connect(autoConnect: false);
      print("Connected to device: ${device.remoteId}");

      final services = await device.discoverServices();
      final imgService = services.firstWhere(
        (s) => s.uuid == svcUuid,
        orElse: () => throw Exception('Custom Image Service not found'),
      );

      final sizeChar = _findChar(imgService, sizeUuid);
      print("Found TEXT_SIZE characteristic: ${sizeChar.uuid}");
      print(
        "Properties: write=${sizeChar.properties.write}, writeWithoutResponse=${sizeChar.properties.writeWithoutResponse}",
      );

      // Create simple 4-byte size data
      final sizeData = ByteData(4)..setUint32(0, testSize, Endian.little);
      final sizeBytes = sizeData.buffer.asUint8List();

      print(
        "Sending size bytes: ${sizeBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
      );

      // Write the size
      await sizeChar.write(sizeBytes, withoutResponse: false);
      print("✅ Size written successfully!");

      // Wait a bit for MCU to process
      print("Waiting for MCU to process...");
      await Future.delayed(Duration(milliseconds: 500));

      // Try to read back to verify
      try {
        final readBack = await sizeChar.read();
        final readValue = ByteData.view(
          Uint8List.fromList(readBack).buffer,
        ).getUint32(0, Endian.little);
        print("Read back: $readValue bytes (expected: $testSize)");

        if (readValue == testSize) {
          print("✅ Size verification successful!");
        } else {
          print("⚠️ Size mismatch - MCU may have modified the value");
        }
      } catch (e) {
        print("⚠️ Could not read back size: $e");
      }

      print("=== TEST COMPLETE ===");
      return true;
    } catch (e) {
      print("❌ Simple TEXT_SIZE test failed: $e");
      return false;
    } finally {
      try {
        await device.disconnect();
        print("Device disconnected");
      } catch (e) {
        print("Error disconnecting: $e");
      }
    }
  }

  /// Test: Send size + image data through both characteristics
  static Future<bool> testImageTransfer(
    BluetoothDevice device,
    int testSize,
  ) async {
    try {
      print("=== IMAGE TRANSFER TEST ===");
      print("Test size: $testSize bytes");

      await device.connect(autoConnect: false);
      print("Connected to device: ${device.remoteId}");

      final services = await device.discoverServices();
      final imgService = services.firstWhere(
        (s) => s.uuid == svcUuid,
        orElse: () => throw Exception('Custom Image Service not found'),
      );

      final sizeChar = _findChar(imgService, sizeUuid);
      final dataChar = _findChar(imgService, dataUuid);

      print("Found characteristics:");
      print("  TEXT_SIZE: ${sizeChar.uuid}");
      print("  TEXT_DATA: ${dataChar.uuid}");
      print(
        "TEXT_DATA properties: write=${dataChar.properties.write}, writeWithoutResponse=${dataChar.properties.writeWithoutResponse}",
      );

      // 1. Send size first
      print("\n--- STEP 1: Sending Size ---");
      final sizeData = ByteData(4)..setUint32(0, testSize, Endian.little);
      final sizeBytes = sizeData.buffer.asUint8List();
      print(
        "Size bytes: ${sizeBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
      );

      await sizeChar.write(sizeBytes, withoutResponse: false);
      print("✅ Size written successfully!");

      // Wait for MCU to process size
      print("Waiting for MCU to process size...");
      await Future.delayed(Duration(milliseconds: 500));

      // 2. Send image data in chunks
      print("\n--- STEP 2: Sending Image Data ---");

      // Create test image data (simple pattern)
      final testImageData = Uint8List(testSize);
      for (int i = 0; i < testSize; i++) {
        testImageData[i] = (i % 256)
            .toInt(); // Simple pattern: 0, 1, 2, 3, ..., 255, 0, 1, ...
      }

      print("Created test image data: ${testImageData.length} bytes");
      print(
        "First 8 bytes: ${testImageData.take(8).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
      );

      // Use small chunks to avoid L2CAP
      final chunkSize = 50; // Very small chunks
      final delay = Duration(milliseconds: 200); // Longer delays

      int sent = 0;
      int chunkCount = 0;

      while (sent < testImageData.length) {
        final end = math.min(sent + chunkSize, testImageData.length);
        final chunk = testImageData.sublist(sent, end);
        chunkCount++;

        print(
          "Sending chunk $chunkCount: bytes ${sent}-${end - 1} (${chunk.length} bytes)",
        );

        try {
          // Always use writeWithResponse to force GATT
          await dataChar.write(chunk, withoutResponse: false);
          sent = end;

          final progress = ((sent * 100) / testImageData.length).floor();
          print("  Progress: $progress% ($sent/${testImageData.length} bytes)");
        } catch (e) {
          print("❌ ERROR sending chunk $chunkCount: $e");
          throw Exception('Failed to send chunk $chunkCount: $e');
        }

        // Wait between chunks
        await Future.delayed(delay);
      }

      print("✅ All image data sent successfully!");
      print("Total chunks: $chunkCount, Total bytes: $sent");

      // Wait for MCU to process
      print("Waiting for MCU to process image data...");
      await Future.delayed(Duration(milliseconds: 1000));

      print("=== IMAGE TRANSFER TEST COMPLETE ===");
      return true;
    } catch (e) {
      print("❌ Image transfer test failed: $e");
      return false;
    } finally {
      try {
        await device.disconnect();
        print("Device disconnected");
      } catch (e) {
        print("Error disconnecting: $e");
      }
    }
  }

  /// Simple method: Send only the image size to TEXT_SIZE characteristic
  static Future<bool> sendImageSizeOnly(
    BluetoothDevice device,
    int imageSize,
  ) async {
    try {
      print("=== SENDING IMAGE SIZE ONLY ===");
      print("Image size: $imageSize bytes");

      await device.connect(autoConnect: false);
      print("Connected to device: ${device.remoteId}");

      // Wait for connection to stabilize
      print("Waiting for connection to stabilize...");
      await Future.delayed(Duration(milliseconds: 500));

      final services = await device.discoverServices();
      final imgService = services.firstWhere(
        (s) => s.uuid == svcUuid,
        orElse: () => throw Exception('Custom Image Service not found'),
      );

      final sizeChar = _findChar(imgService, sizeUuid);
      print("Found TEXT_SIZE characteristic: ${sizeChar.uuid}");
      print(
        "Properties: write=${sizeChar.properties.write}, writeWithoutResponse=${sizeChar.properties.writeWithoutResponse}",
      );

      // Create 4-byte size data (little-endian)
      final sizeData = ByteData(4)..setUint32(0, imageSize, Endian.little);
      final sizeBytes = sizeData.buffer.asUint8List();

      print(
        "Sending size bytes: ${sizeBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}",
      );

      // Write the size
      await sizeChar.write(sizeBytes, withoutResponse: false);
      print("✅ Size written successfully!");

      // Wait a bit for MCU to process
      print("Waiting for MCU to process size...");
      await Future.delayed(Duration(milliseconds: 1000));

      print("=== SIZE SENT SUCCESSFULLY ===");
      return true;
    } catch (e) {
      print("❌ Failed to send image size: $e");
      return false;
    } finally {
      try {
        await device.disconnect();
        print("Device disconnected");
      } catch (e) {
        print("Error disconnecting: $e");
      }
    }
  }

  // Helpers
  static BluetoothCharacteristic _findChar(BluetoothService svc, Guid uuid) {
    return svc.characteristics.firstWhere(
      (c) => c.uuid == uuid,
      orElse: () => throw Exception('Characteristic $uuid not found'),
    );
  }

  static BluetoothCharacteristic? _findCharOrNull(
    BluetoothService svc,
    Guid uuid,
  ) {
    for (final c in svc.characteristics) {
      if (c.uuid == uuid) return c;
    }
    return null;
  }

  static Future<int> _readBatteryLevelFromServices(
    List<BluetoothService> services,
    BluetoothService? imgService,
  ) async {
    BluetoothService? standardBatteryService;
    for (final service in services) {
      if (service.uuid == batterySvcUuid) {
        standardBatteryService = service;
        break;
      }
    }

    if (standardBatteryService != null) {
      final standardBatteryChar = _findCharOrNull(
        standardBatteryService,
        batteryLevelUuid,
      );
      if (standardBatteryChar != null) {
        final value = await standardBatteryChar.read();
        if (value.isNotEmpty) {
          return value.first.clamp(0, 100);
        }
      }
    }

    if (imgService != null) {
      final customBatteryChar = _findCharOrNull(
        imgService,
        customBatteryLevelUuid,
      );
      if (customBatteryChar != null) {
        final value = await customBatteryChar.read();
        if (value.isNotEmpty) {
          return value.first.clamp(0, 100);
        }
      }
    }

    throw Exception('Battery characteristic not found');
  }

  /// Helper: Wait for Bluetooth adapter to be ON
  static Future<void> waitForBluetoothEnabled() async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      return;
    }
    // Wait for state to change to on
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first;
  }
}
