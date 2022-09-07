import 'package:camera/camera.dart';
import 'package:image/image.dart' as imglib;

imglib.Image convertYUV420ToImage(CameraImage cameraImage) {
  int width = cameraImage.width;
  int height = cameraImage.height;
  // print(cameraImage.format.group); ImageFormatGroup.yuv420
  // android.graphics.ImageFormat.YUV_420_888

  // yyyy
  // yyyy
  // yyyy
  // uu
  // uu
  // vv
  // vv

  int yRowStride = cameraImage.planes[0].bytesPerRow;
  int uvRowStride = cameraImage.planes[1].bytesPerRow;
  int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

  final image = imglib.Image(width, height);

  for (var h = 0; h < height; h++) {
    for (var w = 0; w < width; w++) {
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
  int oY = y - 16;
  int oU = u - 128;
  int oV = v - 128;

  int r = (1.164 * oY + 1.793 * oV).round().clamp(0, 255);
  int g = (1.164 * oY - 0.213 * oU - 0.533 * oV).round().clamp(0, 255);
  int b = (1.164 * oY + 2.112 * oU).round().clamp(0, 255);

/*
  int r = (y + v * 1436 / 1024 - 179).round();
  int g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
  int b = (y + u * 1814 / 1024 - 227).round();

  // Clipping RGB values to be inside boundaries [ 0 , 255 ]
  r = r.clamp(0, 255);
  g = g.clamp(0, 255);
  b = b.clamp(0, 255);
  */

  return 0xff000000 | ((b << 16) & 0x00ff0000) | ((g << 8) & 0x0000ff00) | (r & 0x000000ff);
}
