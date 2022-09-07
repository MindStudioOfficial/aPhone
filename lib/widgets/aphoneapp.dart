import 'package:aphone/main.dart';
import 'package:aphone/ndi/ndisend.dart';
import 'package:aphone/service/logging.dart';
import 'package:aphone/util/image.dart';
import 'package:aphone/widgets/camerapreview.dart';
import 'package:aphone/widgets/cameraselector.dart';
import 'package:aphone/widgets/fittedplayer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';

import 'package:ffi/ffi.dart';
import 'dart:ffi';
import 'dart:io';

import 'dart:ui' as ui;

import 'package:osc/osc.dart';
import 'package:ansicolor/ansicolor.dart';

import 'package:video_player/video_player.dart';
import 'package:vibration/vibration.dart';
import 'package:path_provider/path_provider.dart';

import 'package:aphone/ndi/bindings/ndi_ffi_bindings.dart';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as imgLib;

/// Camera example home widget.
class APhoneApp extends StatefulWidget {
  /// Default Constructor
  const APhoneApp({Key? key}) : super(key: key);

  @override
  State<APhoneApp> createState() {
    return _APhoneAppState();
  }
}

class _APhoneAppState extends State<APhoneApp> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  bool isStreaming = false;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  late AnimationController _flashModeControlRowAnimationController;
  late Animation<double> _flashModeControlRowAnimation;
  late AnimationController _exposureModeControlRowAnimationController;
  late Animation<double> _exposureModeControlRowAnimation;
  late AnimationController _focusModeControlRowAnimationController;
  late Animation<double> _focusModeControlRowAnimation;

  // Counting pointers (number of user fingers on screen)
  //int _pointers = 0;

  //OSC
  final osc = OSCSocket(serverPort: 9000);
  final greenPen = AnsiPen()..green(bold: true);
  final bluePen = AnsiPen()..blue(bold: true);
  final grayPen = AnsiPen()..gray(level: 0.5);

  double _minAvailableZoom = 0.1;
  double _maxAvailableZoom = 2.0;

  //Websocket
  //WebSocket? ws;

  final camKey = GlobalKey();
  ui.Image? img;
  late NDIFrame frame;
  late Pointer<Uint8> pData;
  late int maxLen = 0; //resX * resY * 4;
  // Timer? timer;

  int lastTimeSent = 0;

  @override
  void initState() {
    super.initState();

    osc.listen(onOSCData);

    pData = calloc.call<Uint8>(maxLen);

    // Future.delayed(const Duration(milliseconds: 10), () {
    //   timer = Timer.periodic(
    //       Duration(
    //         milliseconds: 500 ~/ (frame.frameRateN / frame.frameRateD),
    //       ), (t) {
    //     update();
    //   });
    // });

    _ambiguate(WidgetsBinding.instance)?.addObserver(this);

    _flashModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashModeControlRowAnimation = CurvedAnimation(
      parent: _flashModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _exposureModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _exposureModeControlRowAnimation = CurvedAnimation(
      parent: _exposureModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );
    _focusModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusModeControlRowAnimation = CurvedAnimation(
      parent: _focusModeControlRowAnimationController,
      curve: Curves.easeInCubic,
    );

    onNewCameraSelected(cameras[0]);
  }

  void onOSCData(msg) async {
    dPrint("${grayPen('received:')} ${bluePen(msg.toString())}");
    //socket.reply(OSCMessage('/received', arguments: []));

    switch (msg.address) {
      case "/stream":
        dPrint("Stream set " + msg.arguments[0].toString());
        setStreamingMode(msg.arguments[0] == 1);
        break;

      case "/autoFocus":
        dPrint("Auto Focus set " + msg.arguments[0].toString());
        setFocusMode(msg.arguments[0] == 1 ? FocusMode.auto : FocusMode.locked);
        break;

      case "/autoExposure":
        dPrint("Auto Exposure set " + msg.arguments[0].toString());
        setExposureMode(msg.arguments[0] == 1 ? ExposureMode.auto : ExposureMode.locked);
        break;

      case "/exposure":
        dPrint("Exposure set " + msg.arguments[0].toString());
        setExposureOffset(msg.arguments[0]);
        break;

      case "/focusPoint":
        dPrint("Focus point set " + msg.arguments[0].toString() + "," + msg.arguments[1].toString());

        break;

      case "/flash":
        dPrint("Flash set " + msg.arguments[0].toString());
        onSetFlashModeButtonPressed(msg.arguments[0] == 1 ? FlashMode.torch : FlashMode.off);
        break;

      case "/vibrate":
        dPrint("Vibrate " + msg.arguments[0].toString());
        Vibration.vibrate(duration: ((msg.arguments[0] as double) * 1000).round());
        break;

      case "/play":
        dPrint("Play media " + msg.arguments[0].toString());
        Directory? libDir = await getExternalStorageDirectory();
        var filename = msg.arguments[0].toString();
        videoFile = XFile(libDir!.path + "/$filename");
        _startVideoPlayer();
        break;

      case "/stop":
        dPrint("Stop media");
        videoFile = null;
        videoController!.pause();
        setState(() {});
        break;
    }
  }

  @override
  void dispose() {
    _ambiguate(WidgetsBinding.instance)?.removeObserver(this);
    _flashModeControlRowAnimationController.dispose();
    _exposureModeControlRowAnimationController.dispose();

    //timer?.cancel();
    ndiSend.stopSendFrames();
    calloc.free(pData);

    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      onNewCameraSelected(cameraController.description);
    }
  }
  // #enddocregion AppLifecycle

  Future<void> capture() async {
    final boundary = camKey.currentContext?.findRenderObject() as RenderRepaintBoundary;

    img = await boundary.toImage();
    final bytes = await img!.toByteData(format: ui.ImageByteFormat.rawRgba);

    pData.asTypedList(maxLen).setRange(
          0,
          bytes!.lengthInBytes < maxLen ? bytes.lengthInBytes : maxLen,
          bytes.buffer.asUint8List(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RepaintBoundary(
          key: camKey,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black,
            ),
            child: (videoController != null && videoController!.value.isPlaying)
                ? FittedPlayer(videoController: videoController!)
                : _liveCamera(),
          ),
        ),
      ),
    );
  }

  Widget _liveCamera() {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Center(
            child: CameraPreviewWidget(
              cameraController: controller!,
              onViewFinderTap: onViewFinderTap,
              maxAvailableZoom: _maxAvailableZoom,
              minAvailableZoom: _minAvailableZoom,
            ),
          ),
        ),
        //_captureControlRowWidget(),
        Container(
          decoration: const BoxDecoration(
            color: Color.fromARGB(255, 44, 44, 44),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modeControlRowWidget(),
              CameraSelector(
                controller: controller,
                onCameraSelected: onNewCameraSelected,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Display a bar with buttons to change the flash and exposure modes
  Widget _modeControlRowWidget() {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.flash_on),
              color: Colors.blue,
              onPressed: controller != null ? onFlashModeButtonPressed : null,
            ),
            // The exposure and focus mode are currently not supported on the web.
            ...!kIsWeb
                ? <Widget>[
                    IconButton(
                      icon: const Icon(Icons.exposure),
                      color: Colors.blue,
                      onPressed: controller != null ? onExposureModeButtonPressed : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_center_focus),
                      color: Colors.blue,
                      onPressed: controller != null ? onFocusModeButtonPressed : null,
                    )
                  ]
                : <Widget>[],
            IconButton(
              icon: const Icon(Icons.wifi_tethering),
              color: isStreaming ? Colors.red : Colors.grey,
              onPressed: controller != null ? onStreamingButtonPressed : null,
            ),
          ],
        ),
        _flashModeControlRowWidget(),
        _exposureModeControlRowWidget(),
        _focusModeControlRowWidget(),
      ],
    );
  }

  Widget _flashModeControlRowWidget() {
    return SizeTransition(
      sizeFactor: _flashModeControlRowAnimation,
      child: ClipRect(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.flash_off),
              color: controller?.value.flashMode == FlashMode.off ? Colors.orange : Colors.blue,
              onPressed: controller != null ? () => onSetFlashModeButtonPressed(FlashMode.off) : null,
            ),
            IconButton(
              icon: const Icon(Icons.flash_auto),
              color: controller?.value.flashMode == FlashMode.auto ? Colors.orange : Colors.blue,
              onPressed: controller != null ? () => onSetFlashModeButtonPressed(FlashMode.auto) : null,
            ),
            IconButton(
              icon: const Icon(Icons.flash_on),
              color: controller?.value.flashMode == FlashMode.always ? Colors.orange : Colors.blue,
              onPressed: controller != null ? () => onSetFlashModeButtonPressed(FlashMode.always) : null,
            ),
            IconButton(
              icon: const Icon(Icons.highlight),
              color: controller?.value.flashMode == FlashMode.torch ? Colors.orange : Colors.blue,
              onPressed: controller != null ? () => onSetFlashModeButtonPressed(FlashMode.torch) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _exposureModeControlRowWidget() {
    final ButtonStyle styleAuto = TextButton.styleFrom(
      // TODO(darrenaustin): Migrate to new API once it lands in stable: https://github.com/flutter/flutter/issues/105724
      // ignore: deprecated_member_use
      primary: controller?.value.exposureMode == ExposureMode.auto ? Colors.orange : Colors.blue,
    );
    final ButtonStyle styleLocked = TextButton.styleFrom(
      // TODO(darrenaustin): Migrate to new API once it lands in stable: https://github.com/flutter/flutter/issues/105724
      // ignore: deprecated_member_use
      primary: controller?.value.exposureMode == ExposureMode.locked ? Colors.orange : Colors.blue,
    );

    return SizeTransition(
      sizeFactor: _exposureModeControlRowAnimation,
      child: ClipRect(
        child: Container(
          color: Colors.grey.shade50,
          child: Column(
            children: <Widget>[
              const Center(
                child: Text('Exposure Mode'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    style: styleAuto,
                    onPressed: controller != null ? () => onSetExposureModeButtonPressed(ExposureMode.auto) : null,
                    onLongPress: () {
                      if (controller != null) {
                        controller!.setExposurePoint(null);
                        showInSnackBar('Resetting exposure point');
                      }
                    },
                    child: const Text('AUTO'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed: controller != null ? () => onSetExposureModeButtonPressed(ExposureMode.locked) : null,
                    child: const Text('LOCKED'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed: controller != null ? () => controller!.setExposureOffset(0.0) : null,
                    child: const Text('RESET OFFSET'),
                  ),
                ],
              ),
              const Center(
                child: Text('Exposure Offset'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Text(_minAvailableExposureOffset.toString()),
                  Slider(
                    value: _currentExposureOffset,
                    min: _minAvailableExposureOffset,
                    max: _maxAvailableExposureOffset,
                    label: _currentExposureOffset.toString(),
                    onChanged: _minAvailableExposureOffset == _maxAvailableExposureOffset ? null : setExposureOffset,
                  ),
                  Text(_maxAvailableExposureOffset.toString()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _focusModeControlRowWidget() {
    final ButtonStyle styleAuto = TextButton.styleFrom(
      // TODO(darrenaustin): Migrate to new API once it lands in stable: https://github.com/flutter/flutter/issues/105724
      // ignore: deprecated_member_use
      primary: controller?.value.focusMode == FocusMode.auto ? Colors.orange : Colors.blue,
    );
    final ButtonStyle styleLocked = TextButton.styleFrom(
      // TODO(darrenaustin): Migrate to new API once it lands in stable: https://github.com/flutter/flutter/issues/105724
      // ignore: deprecated_member_use
      primary: controller?.value.focusMode == FocusMode.locked ? Colors.orange : Colors.blue,
    );

    return SizeTransition(
      sizeFactor: _focusModeControlRowAnimation,
      child: ClipRect(
        child: Container(
          color: Colors.grey.shade50,
          child: Column(
            children: <Widget>[
              const Center(
                child: Text('Focus Mode'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    style: styleAuto,
                    onPressed: controller != null ? () => onSetFocusModeButtonPressed(FocusMode.auto) : null,
                    onLongPress: () {
                      if (controller != null) {
                        controller!.setFocusPoint(null);
                      }
                      showInSnackBar('Resetting focus point');
                    },
                    child: const Text('AUTO'),
                  ),
                  TextButton(
                    style: styleLocked,
                    onPressed: controller != null ? () => onSetFocusModeButtonPressed(FocusMode.locked) : null,
                    child: const Text('LOCKED'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    final CameraController? oldController = controller;
    if (oldController != null) {
      // `controller` needs to be set to null before getting disposed,
      // to avoid a race condition when we use the controller that is being
      // disposed. This happens when camera permission dialog shows up,
      // which triggers `didChangeAppLifecycleState`, which disposes and
      // re-creates the controller.
      controller = null;
      try {
        if (isStreaming) oldController.stopImageStream();
      } on CameraException catch (e) {
        showCameraException(e);
      }

      await oldController.dispose();
    }

    ResolutionPreset cameraRes = ResolutionPreset.veryHigh;

    final CameraController cameraController = CameraController(
      cameraDescription,
      cameraRes,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar('Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();

      if (isStreaming) await cameraController.startImageStream(sendCameraImage);

      // The exposure mode is currently not supported on the web.
      if (!kIsWeb) {
        _minAvailableExposureOffset = await cameraController.getMinExposureOffset();
        _maxAvailableExposureOffset = await cameraController.getMaxExposureOffset();
      }
      _maxAvailableZoom = await cameraController.getMaxZoomLevel();
      _minAvailableZoom = await cameraController.getMinZoomLevel();
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
          break;
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
          break;
        default:
          showCameraException(e);
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onFlashModeButtonPressed() {
    if (_flashModeControlRowAnimationController.value == 1) {
      _flashModeControlRowAnimationController.reverse();
    } else {
      _flashModeControlRowAnimationController.forward();
      _exposureModeControlRowAnimationController.reverse();
      _focusModeControlRowAnimationController.reverse();
    }
  }

  void onExposureModeButtonPressed() {
    if (_exposureModeControlRowAnimationController.value == 1) {
      _exposureModeControlRowAnimationController.reverse();
    } else {
      _exposureModeControlRowAnimationController.forward();
      _flashModeControlRowAnimationController.reverse();
      _focusModeControlRowAnimationController.reverse();
    }
  }

  void onFocusModeButtonPressed() {
    if (_focusModeControlRowAnimationController.value == 1) {
      _focusModeControlRowAnimationController.reverse();
    } else {
      _focusModeControlRowAnimationController.forward();
      _flashModeControlRowAnimationController.reverse();
      _exposureModeControlRowAnimationController.reverse();
    }
  }

  void onStreamingButtonPressed() {
    setStreamingMode(!isStreaming);
  }

  void onSetFlashModeButtonPressed(FlashMode mode) {
    setFlashMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Flash mode set to ${mode.toString().split('.').last}');
    });
  }

  void onSetExposureModeButtonPressed(ExposureMode mode) {
    setExposureMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Exposure mode set to ${mode.toString().split('.').last}');
    });
  }

  void onSetFocusModeButtonPressed(FocusMode mode) {
    setFocusMode(mode).then((_) {
      if (mounted) {
        setState(() {});
      }
      showInSnackBar('Focus mode set to ${mode.toString().split('.').last}');
    });
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFlashMode(mode);
    } on CameraException catch (e) {
      showCameraException(e);
      //rethrow;
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setExposureMode(mode);
    } on CameraException catch (e) {
      showCameraException(e);
      //rethrow;
    }
  }

  Future<void> setExposureOffset(double offset) async {
    if (controller == null) {
      return;
    }

    setState(() {
      _currentExposureOffset = offset;
    });
    try {
      offset = await controller!.setExposureOffset(offset);
    } on CameraException catch (e) {
      showCameraException(e);
      //rethrow;
    }
  }

  Future<void> setFocusMode(FocusMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFocusMode(mode);
    } on CameraException catch (e) {
      showCameraException(e);
      //rethrow;
    }
  }

  Future<void> setStreamingMode(bool mode) async {
    if (controller == null) {
      return;
    }

    isStreaming = mode;
    try {
      if (isStreaming) {
        await controller!.startImageStream(sendCameraImage);
      } else {
        await controller!.stopImageStream();
      }
      maxLen = 0;
    } on CameraException catch (e) {
      showCameraException(e);
      //rethrow;
    }
  }

  Future<void> _startVideoPlayer() async {
    if (videoFile == null) {
      return;
    }

    final VideoPlayerController vController =
        kIsWeb ? VideoPlayerController.network(videoFile!.path) : VideoPlayerController.file(File(videoFile!.path));

    videoPlayerListener = () {
      if (videoController != null) {
        // Refreshing the state to update video player with the correct ratio.
        if (mounted) {
          setState(() {});
        }
        videoController!.removeListener(videoPlayerListener!);
      }
    };
    vController.addListener(videoPlayerListener!);
    //await vController.setLooping(true);
    await vController.initialize();
    await videoController?.dispose();
    if (mounted) {
      setState(() {
        imageFile = null;
        videoController = vController;
      });
    }
    await vController.play();
  }

  //From camera streaming, send camera to NDI
  void sendCameraImage(CameraImage image) {
    if (!isStreaming) return;

    dPrint(image.width.toString() + " / " + controller!.resolutionPreset.name);
    //return;

    int totalBytes = image.planes[0].bytes.length + image.planes[1].bytes.length + image.planes[2].bytes.length;

    //dPrint("image width " + image.width.toString());

    // if last length doesnt match because of size difference
    if (totalBytes != maxLen) {
      //dPrint("Update frame infos");
      ndiSend.stopSendFrames();

      calloc.free(pData);

      maxLen = totalBytes;
      pData = calloc.call<Uint8>(maxLen);
      frame = NDIFrame(
        width: image.width,
        height: image.height,
        fourCC: NDIlib_FourCC_video_type_e.NDIlib_FourCC_video_type_NV12,
        pDataA: pData.address,
        format: NDIlib_frame_format_type_e.NDIlib_frame_format_type_progressive,
        bytesPerPixel: 2,
        frameRateN: 30000,
        frameRateD: 1000,
      );

      ndiSend.sendFrames(frame);
    }

    int t = DateTime.now().millisecondsSinceEpoch;
    if (t < lastTimeSent + 50) {
      //dPrint("skip");
      return;
    }

    //dPrint("send");

    //imgLib.Image img = convertYUV420ToImage(image);
    // var bytes = img.getBytes();

    int offset = 0;
    for (int i = 0; i < 3; i++) {
      int index = i;
      pData.asTypedList(maxLen).setRange(
            offset,
            offset + image.planes[index].bytes.length,
            image.planes[index].bytes.buffer.asUint8List(),
          );
      offset += image.planes[index].bytesPerRow;
    }

    ndiSend.updateFrame(frame);

    lastTimeSent = t;
  }
}

/// This allows a value of type T or T? to be treated as a value of type T?.
///
/// We use this so that APIs that have become non-nullable can still be used
/// with `!` and `?` on the stable branch.
// TODO(ianh): Remove this once we roll stable in late 2021.
T? _ambiguate<T>(T? value) => value;
