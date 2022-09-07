import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewWidget extends StatelessWidget {
  final CameraController? cameraController;

  final void Function(TapDownDetails details, BoxConstraints constraints) onViewFinderTap;
  CameraPreviewWidget({
    Key? key,
    required this.cameraController,
    required this.onViewFinderTap,
    required this.minAvailableZoom,
    required this.maxAvailableZoom,
  }) : super(key: key);

  int _pointers = 0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  final double minAvailableZoom;
  final double maxAvailableZoom;

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Color.fromARGB(255, 121, 121, 121),
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          cameraController!,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onTapDown: (TapDownDetails details) => onViewFinderTap(details, constraints),
              );
            },
          ),
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (cameraController == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale).clamp(minAvailableZoom, maxAvailableZoom);

    await cameraController!.setZoomLevel(_currentScale);
  }
}
