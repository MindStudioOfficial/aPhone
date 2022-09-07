import 'package:aphone/main.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraSelector extends StatelessWidget {
  final CameraController? controller;
  final void Function(CameraDescription description) onCameraSelected;
  const CameraSelector({
    Key? key,
    required this.onCameraSelected,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cameras.length,
        shrinkWrap: true,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: IconButton(
              onPressed: () {
                onCameraSelected(cameras[index]);
              },
              icon: Icon(
                getCameraLensIcon(cameras[index].lensDirection),
                color: controller?.description == cameras[index] ? Colors.blue : Colors.grey,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Returns a suitable camera icon for [direction].
  IconData getCameraLensIcon(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return Icons.camera_rear;
      case CameraLensDirection.front:
        return Icons.camera_front;
      case CameraLensDirection.external:
        return Icons.camera;
      default:
        throw ArgumentError('Unknown lens direction');
    }
  }
}
