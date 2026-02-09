import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Needed to get Guard Info
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/theme.dart';

class ScanTicketScreen extends StatefulWidget {
  final String eventId;

  const ScanTicketScreen({super.key, required this.eventId});

  @override
  State<ScanTicketScreen> createState() => _ScanTicketScreenState();
}

class _ScanTicketScreenState extends State<ScanTicketScreen> with SingleTickerProviderStateMixin {
  late MobileScannerController _cameraController;
  bool _isScanning = true;
  bool _isEntryMode = true; // TOGGLE: True = Entry, False = Exit

  // --- GUARD INFO ---
  String _guardName = "Unknown Guard";
  String _guardId = "";

  // --- SECURITY CONFIGURATION ---
  // QR Code sirf 8 seconds tak valid rahay ga (5s refresh + 3s buffer)
  final int _maxQrAgeSeconds = 8;

  @override
  void initState() {
    super.initState();
    _fetchGuardDetails(); // Get who is scanning
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
      torchEnabled: false,
    );
  }

  // --- FETCH GUARD DETAILS (UPDATED: FLAT STRUCTURE) ---
  Future<void> _fetchGuardDetails() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _guardId = user.uid;

        // [FLAT STRUCTURE UPDATE]
        // Ab Admin ho ya Guard, sab 'users' collection main hain.
        // Alag se 'admin' collection check karne ki zaroorat nahi.

        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          setState(() {
            _guardName = userDoc.get('fullName') ?? "Guard";
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching guard info: $e");
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  // --- 1. HANDLE SCAN ---
  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() => _isScanning = false); // Pause scanning
        _processQrCode(barcode.rawValue!);
        break;
      }
    }
  }

  // --- 2. PROCESS QR DATA (INTELLIGENT SECURITY CHECK) ---
  Future<void> _processQrCode(String qrData) async {
    try {
      // Expected Format: EventID|UserID|Timestamp
      List<String> parts = qrData.split('|');

      if (parts.length < 3) {
        _showErrorDialog("Invalid Ticket", "Security token missing.\nPlease ask student to update/refresh app.");
        return;
      }

      String qrEventId = parts[0];
      String userId = parts[1];
      String timeString = parts[2];

      // --- A. SECURITY CHECK: SCREENSHOT DETECTION ---
      int? qrTime = int.tryParse(timeString);
      if (qrTime == null) {
        _showErrorDialog("Corrupted Data", "Invalid timestamp format.");
        return;
      }

      int currentTime = DateTime.now().millisecondsSinceEpoch;
      // Calculate difference in seconds
      int diffSeconds = (currentTime - qrTime) ~/ 1000;

      // Agar QR code 8 seconds se purana hai -> Reject (It's a screenshot or old code)
      if (diffSeconds > _maxQrAgeSeconds) {
        _showErrorDialog(
            "SCREENSHOT DETECTED",
            "This QR code expired ${diffSeconds - _maxQrAgeSeconds} seconds ago.\n\nStatic screenshots are NOT allowed.\nAsk the student to open the live app."
        );
        return;
      }

      // --- B. CHECK EVENT MATCH ---
      if (qrEventId != widget.eventId) {
        _showErrorDialog("Wrong Event", "This ticket is for another event.\nExpected: ${widget.eventId}");
        return;
      }

      // --- C. VALIDATE USER & STATUS ---
      await _validateAndAct(userId);

    } catch (e) {
      _showErrorDialog("Scan Error", "Could not process ticket: $e");
    }
  }

  // --- 3. VALIDATE STATUS & ACT (FLAT STRUCTURE COMPATIBLE) ---
  Future<void> _validateAndAct(String userId) async {
    try {
      // Fetch User Details from 'users' collection (Flat Structure)
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        _showErrorDialog("User Not Found", "This student does not exist in the database.");
        return;
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Check Attendance Status in Sub-collection (Events -> Attendance)
      DocumentReference attendanceRef = FirebaseFirestore.instance
          .collection('events').doc(widget.eventId)
          .collection('attendance').doc(userId);

      DocumentSnapshot attendanceDoc = await attendanceRef.get();

      // Default status is 'outside' if no record exists
      String currentStatus = attendanceDoc.exists ? (attendanceDoc['status'] ?? 'outside') : 'outside';

      // --- LOGIC GATES ---
      if (_isEntryMode) {
        // --- ENTRY MODE ---
        if (currentStatus == 'inside') {
          _showErrorDialog("Already Inside", "${userData['fullName']} has already entered.");
        } else {
          // Success: Mark Inside
          await attendanceRef.set({
            'status': 'inside',
            'lastEntry': FieldValue.serverTimestamp(),
            'name': userData['fullName'],
            'regId': userData['studentId'] ?? userData['sapId'] ?? 'N/A', // Handle both ID types
            'program': userData['program'] ?? 'N/A',
            // --- NEW: Save Guard Info ---
            'guardName': _guardName,
            'guardId': _guardId,
          }, SetOptions(merge: true));

          _showSuccessCard(userData, "You can go INSIDE now", Colors.green, Icons.login);
        }
      } else {
        // --- EXIT MODE ---
        if (currentStatus == 'outside') {
          _showErrorDialog("Already Outside", "${userData['fullName']} is already outside.");
        } else {
          // Success: Mark Outside
          await attendanceRef.set({
            'status': 'outside',
            'lastExit': FieldValue.serverTimestamp(),
            // --- NEW: Save Guard Info ---
            'guardName': _guardName,
            'guardId': _guardId,
          }, SetOptions(merge: true));

          _showSuccessCard(userData, "You can go OUTSIDE now", Colors.orange, Icons.logout);
        }
      }

    } catch (e) {
      _showErrorDialog("Database Error", e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.white, onPressed: () => Navigator.pop(context)),
        title: const Text("Secure Scanner", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _cameraController.toggleTorch(),
            icon: ValueListenableBuilder(
              valueListenable: _cameraController,
              builder: (context, value, child) {
                return Icon(value.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off, color: Colors.white);
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _cameraController, onDetect: _onDetect),

          // Custom Overlay
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: _isEntryMode ? Colors.green : Colors.orange,
                borderRadius: 20,
                borderLength: 40,
                borderWidth: 10,
                cutOutSize: size.width * 0.7,
                overlayColor: Colors.black.withOpacity(0.7),
              ),
            ),
          ),

          // --- TOP MODE SWITCHER ---
          Positioned(
            top: 100, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  _buildModeButton("ENTRY", true, Colors.green),
                  _buildModeButton("EXIT", false, Colors.orange),
                ],
              ),
            ),
          ),

          // --- BOTTOM STATUS ---
          Positioned(
            bottom: 80, left: 0, right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(30)),
                  child: Text(
                      _isScanning ? "Align Ticket QR Code" : "Validating...",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)
                  ),
                ),
                if (!_isScanning) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: Colors.white),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildModeButton(String label, bool isEntry, Color color) {
    bool isSelected = _isEntryMode == isEntry;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isEntryMode = isEntry),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  // --- SUCCESS CARD ---
  void _showSuccessCard(Map<String, dynamic> userData, String message, Color color, IconData icon) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Text("APPROVED", style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // User Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              backgroundImage: (userData['profileImage'] != null && userData['profileImage'] != '')
                  ? NetworkImage(userData['profileImage'])
                  : null,
              child: (userData['profileImage'] == null || userData['profileImage'] == '')
                  ? Icon(Icons.person, size: 40, color: Theme.of(context).primaryColor)
                  : null,
            ),
            const SizedBox(height: 16),

            // User Info
            Text(
              userData['fullName'] ?? 'Unknown',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            Text(userData['studentId'] ?? userData['sapId'] ?? 'N/A', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                "${userData['program']} - ${userData['department']}",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const Divider(height: 30),

            Text(
                message,
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center
            ),

            const SizedBox(height: 30),

            // OK Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Add delay to prevent instant rescan
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _isScanning = true);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("Scan Next", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ERROR DIALOG ---
  void _showErrorDialog(String title, String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
          ],
        ),
        content: Text(msg, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Small delay before resuming camera
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) setState(() => _isScanning = true);
              });
            },
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

// Custom Overlay Shape
class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 10.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..fillType = PathFillType.evenOdd..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path _getLeftTopPath(Rect rect) {
      return Path()..moveTo(rect.left, rect.bottom)..lineTo(rect.left, rect.top)..lineTo(rect.right, rect.top);
    }
    return _getLeftTopPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final height = rect.height;
    final borderOffset = borderWidth / 2;
    final _cutOutSize = cutOutSize < width ? cutOutSize : width - borderLength;

    final backgroundPaint = Paint()..color = overlayColor..style = PaintingStyle.fill;
    final borderPaint = Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = borderWidth;

    final cutOutRect = Rect.fromLTWH(
      rect.left + width / 2 - _cutOutSize / 2 + borderOffset,
      rect.top + height / 2 - _cutOutSize / 2 + borderOffset,
      _cutOutSize - borderWidth,
      _cutOutSize - borderWidth,
    );

    canvas.saveLayer(rect, backgroundPaint);
    canvas.drawRect(rect, backgroundPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)), Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    final path = Path()
      ..moveTo(cutOutRect.left, cutOutRect.top + borderLength)
      ..lineTo(cutOutRect.left, cutOutRect.top + borderRadius)
      ..arcToPoint(Offset(cutOutRect.left + borderRadius, cutOutRect.top), radius: Radius.circular(borderRadius), clockwise: true)
      ..lineTo(cutOutRect.left + borderLength, cutOutRect.top)
      ..moveTo(cutOutRect.right - borderLength, cutOutRect.top)
      ..lineTo(cutOutRect.right - borderRadius, cutOutRect.top)
      ..arcToPoint(Offset(cutOutRect.right, cutOutRect.top + borderRadius), radius: Radius.circular(borderRadius), clockwise: true)
      ..lineTo(cutOutRect.right, cutOutRect.top + borderLength)
      ..moveTo(cutOutRect.right, cutOutRect.bottom - borderLength)
      ..lineTo(cutOutRect.right, cutOutRect.bottom - borderRadius)
      ..arcToPoint(Offset(cutOutRect.right - borderRadius, cutOutRect.bottom), radius: Radius.circular(borderRadius), clockwise: true)
      ..lineTo(cutOutRect.right - borderLength, cutOutRect.bottom)
      ..moveTo(cutOutRect.left + borderLength, cutOutRect.bottom)
      ..lineTo(cutOutRect.left + borderRadius, cutOutRect.bottom)
      ..arcToPoint(Offset(cutOutRect.left, cutOutRect.bottom - borderRadius), radius: Radius.circular(borderRadius), clockwise: true)
      ..lineTo(cutOutRect.left, cutOutRect.bottom - borderLength);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }
}