// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart' as ffi;
import 'bindings/ndi_ffi_bindigs.dart';

NDIffi _ndi = NDIffi(DynamicLibrary.open("libndi.so"));
final String sName = "Phone 1";

class NDISend {
  NDISend(String sname) {
    _ndi.NDIlib_v5_load();
    if (!_ndi.NDIlib_initialize()) {
      throw Exception("Could not initialize NDI");
    }

  }

  ReceivePort? _sendReceivePort;
  Isolate? _sendIsolate;
  SendPort? _sendSendPort;

  Pointer? _pSendInstance;
  Pointer? _pSendSettings;
  Pointer? _pSendName;


  Future<void> sendFrames(NDIFrame frame) async {
    final completer = Completer();
    _sendReceivePort = ReceivePort();
    _sendReceivePort!.listen((data) {
      if (data is SendPort) {
        _sendSendPort = data;
      }
      if (data is Map<String, int>) {
        if (data["pSendInstance"] != null && data["pSendSettings"] != null && data["pSendName"] != null) {
          _pSendInstance = Pointer.fromAddress(data["pSendInstance"]!);
          _pSendSettings = Pointer.fromAddress(data["pSendSettings"]!);
          _pSendName = Pointer.fromAddress(data["pSendName"]!);
        }
      }
    }, onDone: () {
      print("done sending");
      completer.complete();
    });

    _sendIsolate = await Isolate.spawn(_sendFrames, SendObject(frame: frame, sendPort: _sendReceivePort!.sendPort));
    return completer.future;
  }

  void stopSendFrames() {
    print("stopping");
    if (_sendIsolate != null && _sendReceivePort != null) {
      _sendReceivePort!.close();
      _sendIsolate!.kill(priority: Isolate.immediate);
      _sendIsolate = null;
      _sendReceivePort = null;
    }
    if (_pSendInstance != null) {
      print("destroying send instance");
      _ndi.NDIlib_send_destroy(_pSendInstance!.cast<Void>());
    }
    if (_pSendSettings != null) ffi.calloc.free(_pSendSettings!);
    if (_pSendName != null) ffi.calloc.free(_pSendName!);
    print("stopped");
  }

  void updateFrame(NDIFrame frame) {
    if (_sendSendPort != null) {
      _sendSendPort!.send(frame);
    }
  }

  static void _sendFrames(SendObject object) async {
    ReceivePort receivePort = ReceivePort();
    object.sendPort.send(receivePort.sendPort);

    receivePort.listen((data) {
      if (data is NDIFrame) {
        //print("gotFrame");
        if (!object.frame.destroyed && data.pFrame.address != object.frame.pFrame.address) {
          object.frame.destroy();
          object.frame = data;
        }
      }
    });

    Pointer<NDIlib_send_create_t> pCreateSettings = ffi.calloc.call<NDIlib_send_create_t>(1);
    final pNDIName = sName.toNativeUtf8().cast<Int8>();
    pCreateSettings.ref.p_ndi_name = pNDIName;
    pCreateSettings.ref.clock_audio = 0;
    pCreateSettings.ref.clock_video = 0;
    NDIlib_send_instance_t pSend = _ndi.NDIlib_send_create(pCreateSettings);
    if (pSend == nullptr) {
      print("error creating sender");
    }
    object.sendPort.send(<String, int>{
      "pSendInstance": pSend.address,
      "pSendSettings": pCreateSettings.address,
      "pSendName": pNDIName.address,
    });

    while (true) {
      _ndi.NDIlib_send_send_video_async_v2(pSend, object.frame.pFrame);
      await Future.delayed(
        Duration(milliseconds: 1000 ~/ (object.frame.frameRateN / object.frame.frameRateD)),
      );
    }
  }
}

class SendObject {
  NDIFrame frame;
  SendPort sendPort;
  SendObject({required this.frame, required this.sendPort});
}

class NDIFrame {
  int width;
  int height;
  int timecode;
  int frameRateN;
  int frameRateD;
  int bytesPerPixel;
  int pDataA;
  int fourCC;
  int format;
  bool _destroyed = false;
  late int _pFrameA;

  NDIFrame({
    required this.width,
    required this.height,
    required this.fourCC,
    this.timecode = 0,
    required this.pDataA,
    this.frameRateN = 25000,
    this.frameRateD = 1000,
    required this.format,
    required this.bytesPerPixel,
  }) {
    Pointer<NDIlib_video_frame_v2_t> _pFrame = ffi.calloc.call<NDIlib_video_frame_v2_t>(1);
    _pFrame.ref.FourCC = fourCC;
    _pFrame.ref.xres = width;
    _pFrame.ref.yres = height;
    _pFrame.ref.frame_rate_D = frameRateD;
    _pFrame.ref.frame_rate_N = frameRateN;
    _pFrame.ref.p_data = Pointer.fromAddress(pDataA).cast<Uint8>();
    _pFrame.ref.timecode = timecode;
    _pFrame.ref.picture_aspect_ratio = width / height;
    _pFrame.ref.frame_format_type = format;

    _pFrameA = _pFrame.address;
  }

  Pointer<NDIlib_video_frame_v2_t> get pFrame => Pointer.fromAddress(_pFrameA);
  bool get destroyed => _destroyed;

  destroy() {
    _destroyed = true;
    ffi.calloc.free(Pointer.fromAddress(pDataA));
    ffi.calloc.free(Pointer.fromAddress(_pFrameA));
  }
}
