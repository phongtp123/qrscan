import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';


void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: QRScannerPage(),
    );
  }
}

class QRScannerPage extends StatefulWidget {
  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  MobileScannerController cameraController = MobileScannerController();

  final String serverUrl = 'http://192.168.100.152:8080/DUTParking/monitor'; // Replace with your backend URL
  bool _isScanningEnabled = true; // Trạng thái kiểm soát quét QR
  final Duration scanDelay = Duration(seconds: 10); // Hạn chế quét mỗi 10 giây
  static const String signerkey = "4B8SWV0opYWRgxeKoKost+CvEfqKhCPV0G1SFgU6V1vLOLbBWo5hE1JhpQUV7gWL";
  final BigInt keyAsBigInt = BigInt.parse(
    signerkey.codeUnits.map((unit) => unit.toRadixString(16)).join(''),
    radix: 16,
  );


  Future<String> _generatePassToken(String code) async {
    String? hovaten;
    String? email;
    String? ticketName;
    String? decision;
    int? id;

    String base64EncodedKey = base64Encode(utf8.encode(signerkey));
    final decodedKey = base64Decode(base64EncodedKey);
    final keyAsBigInt = BigInt.parse(decodedKey.map((e) => e.toRadixString(16).padLeft(2, '0')).join(), radix: 16);

    try {
      // Parse the JWT
      final jws = JsonWebSignature.fromCompactSerialization(code);

      // Verify the signature
      final keyStore = JsonWebKeyStore()
        ..addKey(JsonWebKey.symmetric(key: keyAsBigInt));

      final isValid = jws.verify(keyStore);

      if (await isValid) {
        throw Exception("Invalid JWT signature");
      }

      // Parse the claims from the payload
      final claims = jws.unverifiedPayload.jsonContent;

      id = claims["id"];
      hovaten = claims["hovaten"];
      email = claims["email"];
      ticketName = claims["ticketName"];
      decision = "PASS";
    } catch (e) {
      if (e.toString().contains("JWT expired")) {
        decision = "NOT PASS";
      } else {
        print("Invalid JWT: $e");
        decision = "NOT PASS";
      }
    }

    // Create a new JWT with jose
    final claims = JsonWebTokenClaims.fromJson({
      "id": id,
      "hovaten": hovaten,
      "email": email,
      "ticketName": ticketName,
      "decision": decision,
      "iss": "example.com", // Issuer
      "iat": DateTime.now().millisecondsSinceEpoch ~/ 1000, // Issued At
      "exp": DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000, // Expiration
    });

    // Sign the new JWT
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = claims.toJson()
      ..addRecipient(JsonWebKey.symmetric(key: keyAsBigInt), algorithm: "HS256");

    final passToken = builder.build().toCompactSerialization();
    return passToken;
  }

  void _saveDataToServer(String code) async {
    try {
      String passToken = await _generatePassToken(code);
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'passToken': passToken}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request failed!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _handleQRCodeDetection(String code) {
    if (_isScanningEnabled) {
      _isScanningEnabled = false;

      // Xử lý dữ liệu QR code
      print('QR Code Detected: $code');
      _saveDataToServer(code);

      // Khóa quét tạm thời trong 10 giây
      Timer(scanDelay, () {
        setState(() {
          _isScanningEnabled = true;
        });
      });
    } else {
      print('Chờ 10 giây trước khi quét lại.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Scanner'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                cameraController.toggleTorch();
              });
            },
            icon: Icon(
              cameraController.torchEnabled ? Icons.flash_on : Icons.flash_off,
              color: cameraController.torchEnabled ? Colors.yellow : Colors.grey,
            ),
          ),
          IconButton(
            onPressed: () => cameraController.switchCamera(),
            icon: const Icon(Icons.switch_camera),
          ),
        ],
      ),
      body: MobileScanner(
        controller: cameraController,
        onDetect: (BarcodeCapture barcodeCapture) {
          final barcodes = barcodeCapture.barcodes;

          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              final String code = barcode.rawValue!;
              _handleQRCodeDetection(code); // Sử dụng phương thức kiểm soát quét
              break; // Chỉ xử lý mã đầu tiên
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to scan QR code!')),
              );
            }
          }
        },
      ),
    );
  }
}
