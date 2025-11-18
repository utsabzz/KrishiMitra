import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Sensor & Camera',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final flutterReactiveBle = FlutterReactiveBle();

  // BLE UUIDs (UART Service)
  final serviceUuid = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final rxUuid = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
  final txUuid = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

  // BLE variables
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;
  QualifiedCharacteristic? _txCharacteristic;
  QualifiedCharacteristic? _rxCharacteristic;
  DiscoveredDevice? _espDevice;

  // App state
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isLoading = false;
  String _status = "Disconnected";

  // Sensor data
  double _temperature = 0.0;
  double _humidity = 0.0;
  String _soilCondition = "--";
  int _moistureLevel = 0;
  String _rawData = "";
  DateTime _lastUpdate = DateTime.now();

  // ESP32-CAM WiFi
  final TextEditingController _ipController = TextEditingController();
  String _camStatus = "Disconnected";
  bool _isCamConnected = false;
  String _camImageUrl = "";
  bool _isLoadingCam = false;

  @override
  void initState() {
    super.initState();
    _ipController.text = "http://192.168.1.100"; // Default IP
    _checkPermissions();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  void _checkPermissions() {
    print("🔍 Checking BLE permissions...");
  }

  // ========== ESP32 SENSOR (Bluetooth) ==========
  void _startScan() {
    setState(() {
      _isScanning = true;
      _status = "Scanning...";
    });

    print("🔍 Starting BLE scan for ESP32 Sensor...");

    _scanSubscription = flutterReactiveBle.scanForDevices(withServices: []).listen(
      (device) {
        print("📱 Found device: ${device.name} - ${device.id}");
        
        if (device.name == "ESP32_Sensor") {
          print("✅ Found ESP32_Sensor! Stopping scan...");
          setState(() {
            _espDevice = device;
            _isScanning = false;
            _status = "Found ESP32_Sensor";
          });
          _scanSubscription?.cancel();
          _connectToDevice();
        }
      },
      onError: (error) {
        print("❌ Scan error: $error");
        setState(() {
          _isScanning = false;
          _status = "Scan failed: $error";
        });
      },
    );

    // Stop scan after 10 seconds
    Timer(const Duration(seconds: 10), () {
      if (_isScanning) {
        print("⏰ Scan timeout");
        _scanSubscription?.cancel();
        setState(() {
          _isScanning = false;
          _status = "Scan timeout - ESP32 not found";
        });
      }
    });
  }

  void _connectToDevice() {
    if (_espDevice == null) return;

    setState(() {
      _isLoading = true;
      _status = "Connecting...";
    });

    print("🔗 Connecting to ${_espDevice!.name}...");

    _connectionSubscription = flutterReactiveBle
        .connectToDevice(id: _espDevice!.id)
        .listen(
      (connectionState) {
        print("🔌 Connection state: $connectionState");
        
        if (connectionState.connectionState == DeviceConnectionState.connected) {
          print("✅ Connected to ESP32 Sensor!");
          setState(() {
            _isConnected = true;
            _isLoading = false;
            _status = "Connected to Sensor";
          });
          _setupCharacteristics();
        } else if (connectionState.connectionState == DeviceConnectionState.disconnected) {
          print("❌ Disconnected from ESP32");
          setState(() {
            _isConnected = false;
            _isLoading = false;
            _status = "Disconnected";
          });
        }
      },
      onError: (error) {
        print("❌ Connection error: $error");
        setState(() {
          _isConnected = false;
          _isLoading = false;
          _status = "Connection failed: $error";
        });
      },
    );
  }

  void _setupCharacteristics() {
    if (_espDevice == null) return;

    _txCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: txUuid,
      deviceId: _espDevice!.id,
    );

    _rxCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: rxUuid,
      deviceId: _espDevice!.id,
    );

    _listenToSensorData();
  }

  void _listenToSensorData() {
    if (_txCharacteristic == null) return;

    print("👂 Listening for sensor data...");

    _dataSubscription = flutterReactiveBle
        .subscribeToCharacteristic(_txCharacteristic!)
        .listen(
      (data) {
        String receivedData = String.fromCharCodes(data);
        print("📨 Received: $receivedData");
        
        setState(() {
          _rawData = receivedData;
          _lastUpdate = DateTime.now();
        });
        
        _parseSensorData(receivedData);
      },
      onError: (error) {
        print("❌ Data subscription error: $error");
      },
    );
  }

  void _parseSensorData(String data) {
    try {
      if (data.contains("TEMP:") && data.contains("HUM:")) {
        List<String> parts = data.split(',');
        
        for (String part in parts) {
          if (part.startsWith("TEMP:")) {
            setState(() {
              _temperature = double.tryParse(part.split(':')[1]) ?? 0.0;
            });
          } else if (part.startsWith("HUM:")) {
            setState(() {
              _humidity = double.tryParse(part.split(':')[1]) ?? 0.0;
            });
          } else if (part.startsWith("SOIL:")) {
            setState(() {
              _soilCondition = part.split(':')[1];
            });
          } else if (part.startsWith("MOISTURE:")) {
            setState(() {
              _moistureLevel = int.tryParse(part.split(':')[1]) ?? 0;
            });
          }
        }
        
        print("✅ Parsed - Temp: $_temperature, Humidity: $_humidity, Soil: $_soilCondition");
      }
    } catch (e) {
      print("❌ Error parsing sensor data: $e");
    }
  }

  void _sendCommand(String command) {
    if (_rxCharacteristic == null || !_isConnected) return;

    print("📤 Sending command: $command");
    
    flutterReactiveBle.writeCharacteristicWithResponse(
      _rxCharacteristic!,
      value: command.codeUnits,
    );
  }

  void _disconnectSensor() {
    print("🔌 Disconnecting from sensor...");
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _scanSubscription?.cancel();
    
    setState(() {
      _isConnected = false;
      _isScanning = false;
      _isLoading = false;
      _status = "Disconnected";
      _espDevice = null;
    });
  }

  // ========== ESP32-CAM (WiFi) ==========
  Future<void> _connectToCamera() async {
    String ipAddress = _ipController.text.trim();
    if (ipAddress.isEmpty) {
      setState(() {
        _camStatus = "Please enter IP address";
      });
      return;
    }

    // Ensure URL has http:// prefix
    if (!ipAddress.startsWith('http://') && !ipAddress.startsWith('https://')) {
      ipAddress = 'http://$ipAddress';
    }

    setState(() {
      _isLoadingCam = true;
      _camStatus = "Connecting to camera...";
    });

    try {
      // Test connection by fetching the stream URL
      final response = await http.get(Uri.parse('$ipAddress/stream')).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        setState(() {
          _isCamConnected = true;
          _camStatus = "Camera Connected";
          _camImageUrl = '$ipAddress/capture'; // or /stream depending on your ESP32-CAM setup
        });
        print("✅ Camera connected: $ipAddress");
      } else {
        setState(() {
          _isCamConnected = false;
          _camStatus = "Camera connection failed (HTTP ${response.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _isCamConnected = false;
        _camStatus = "Camera connection failed: $e";
      });
      print("❌ Camera connection error: $e");
    } finally {
      setState(() {
        _isLoadingCam = false;
      });
    }
  }

  void _disconnectCamera() {
    setState(() {
      _isCamConnected = false;
      _camStatus = "Disconnected";
      _camImageUrl = "";
    });
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Sensor & Camera'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ========== ESP32-CAM SECTION ==========
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESP32-CAM (WiFi)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              labelText: 'ESP32-CAM IP Address',
                              border: OutlineInputBorder(),
                              hintText: 'http://192.168.1.100',
                              prefixIcon: Icon(Icons.wifi),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _isLoadingCam
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: _isCamConnected ? _disconnectCamera : _connectToCamera,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isCamConnected ? Colors.red : Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(_isCamConnected ? 'Disconnect' : 'Connect'),
                              ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.camera_alt,
                          color: _isCamConnected ? Colors.green : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _camStatus,
                          style: TextStyle(
                            color: _isCamConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Camera Stream/Image
                    if (_isCamConnected)
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _camImageUrl.isNotEmpty
                            ? Image.network(
                                _camImageUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.error, color: Colors.red, size: 40),
                                        SizedBox(height: 8),
                                        Text('Failed to load camera'),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.camera_alt, size: 40, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text('Camera connected'),
                                    Text('Configure ESP32-CAM stream URL'),
                                  ],
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ========== ESP32 SENSOR SECTION ==========
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESP32 Sensor (Bluetooth)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    // Status
                    Row(
                      children: [
                        Icon(
                          Icons.bluetooth,
                          color: _isConnected ? Colors.green : Colors.grey,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _status,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _isConnected ? Colors.green : Colors.red,
                                ),
                              ),
                              if (_espDevice != null)
                                Text(
                                  'Device: ${_espDevice!.name}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_isScanning) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Scanning for ESP32_Sensor...'),
                    ],
                    if (_isLoading) ...[
                      const SizedBox(height: 12),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Connecting...'),
                    ],
                    const SizedBox(height: 16),
                    
                    // Connect Button
                    if (!_isConnected && !_isScanning && !_isLoading)
                      ElevatedButton(
                        onPressed: _startScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text(
                          'Scan for ESP32 Sensor',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    
                    // Disconnect Button
                    if (_isConnected)
                      ElevatedButton(
                        onPressed: _disconnectSensor,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text(
                          'Disconnect Sensor',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),

                    // Sensor Data
                    if (_isConnected) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Sensor Data',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _buildSensorItem(
                        icon: Icons.thermostat,
                        iconColor: Colors.orange,
                        title: 'Temperature',
                        value: '${_temperature.toStringAsFixed(1)} °C',
                      ),
                      _buildSensorItem(
                        icon: Icons.water_drop,
                        iconColor: Colors.blue,
                        title: 'Humidity',
                        value: '${_humidity.toStringAsFixed(1)} %',
                      ),
                      _buildSensorItem(
                        icon: Icons.grass,
                        iconColor: _soilCondition == "DRY" ? Colors.orange : Colors.green,
                        title: 'Soil Moisture',
                        value: _soilCondition,
                      ),
                      _buildSensorItem(
                        icon: Icons.analytics,
                        iconColor: Colors.purple,
                        title: 'Moisture Level',
                        value: '$_moistureLevel%',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last update: ${_formatTime(_lastUpdate)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Raw Data & Controls
                      Card(
                        color: Colors.grey[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              const Text(
                                'Raw Data',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: SelectableText(
                                  _rawData.isEmpty ? "No data received" : _rawData,
                                  style: const TextStyle(fontFamily: 'Monospace', fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => _sendCommand("GET_DATA"),
                                child: const Text('Request Data'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}