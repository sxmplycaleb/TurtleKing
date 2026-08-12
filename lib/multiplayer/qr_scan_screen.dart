import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera scanner for the host's join QR code.
///
/// Pops with the raw scanned payload string as soon as a single QR code is
/// decoded (validating the payload is the join lobby's job — see
/// [JoinPayload.parse]). The user can cancel at any time, which pops with
/// null.
///
/// If the camera cannot start (permission denied, no camera, hardware
/// error), the screen shows a clear user-facing message instead of a dead
/// black preview, and the user can go back to the join lobby.
///
/// This screen is deliberately thin so the join flow stays testable: widget
/// tests never instantiate the camera — they inject a fake scan provider
/// into the join lobby instead.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    // The controller is a ValueNotifier over its state; surface camera
    // failures (e.g. permission denied) as a visible message rather than an
    // unexplained black screen.
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final error = _controller.value.error;
    if (error == null || _handled || !mounted) return;
    setState(() {
      _cameraError = switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'Camera permission was not granted. Allow camera access for this '
              'app, or enter the 6-digit code from the host’s screen instead.',
        MobileScannerErrorCode.unsupported =>
          'QR scanning is not supported on this device. Enter the 6-digit '
              'code from the host’s screen instead.',
        _ =>
          'The camera could not be started. Check the camera permission, '
              'or enter the 6-digit code from the host’s screen instead.',
      };
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    // Single-detection guard: the first valid decode wins and every later
    // callback (mobile_scanner can fire several per frame) is ignored.
    _handled = true;
    _controller.removeListener(_onControllerChanged);
    if (!mounted) return;
    Navigator.of(context).pop(raw);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          // Dim the edges so the center scan window reads clearly.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  border: Border.all(color: Colors.white70, width: 2),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                const Spacer(),
                if (_cameraError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _cameraError!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else ...[
                  Text(
                    'Point the camera at the host’s QR code',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'It appears on the host’s “Host Game” screen.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
