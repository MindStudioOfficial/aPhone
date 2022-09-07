import 'package:camera/camera.dart';
import 'package:image/image.dart' as imglib;

imglib.Image convertYUV420ToImage(CameraImage cameraImage) {
  int width = cameraImage.width;
  int height = cameraImage.height;

  int yRowStride = cameraImage.planes[0].bytesPerRow;
  int uvRowStride = cameraImage.planes[1].bytesPerRow;
  int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

  final image = imglib.Image(width, height);

  for (var w = 0; w < width; w++) {
    for (var h = 0; h < height; h++) {
      int uvIndex = uvPixelStride * (w / 2).floor() + uvRowStride * (h / 2).floor();
      int index = h * width + w;
      int yIndex = h * yRowStride + w;

      int y = cameraImage.planes[0].bytes[yIndex];
      int u = cameraImage.planes[1].bytes[uvIndex];
      int v = cameraImage.planes[2].bytes[uvIndex];

      image.data[index] = yuv2rgb(y, u, v);
    }
  }
  return image;
}

int yuv2rgb(int y, int u, int v) {
  // Convert yuv pixel to rgb
  int r = (y + v * 1436 / 1024 - 179).round();
  int g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
  int b = (y + u * 1814 / 1024 - 227).round();

  // Clipping RGB values to be inside boundaries [ 0 , 255 ]
  r = r.clamp(0, 255);
  g = g.clamp(0, 255);
  b = b.clamp(0, 255);

  return 0xff000000 | ((b << 16) & 0xff0000) | ((g << 8) & 0xff00) | (r & 0xff);
}
