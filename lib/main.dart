// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:aphone/widgets/aphoneapp.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ndi/ndisend.dart';

import 'package:aphone/service/logging.dart';

List<CameraDescription> cameras = <CameraDescription>[];
late NDISend ndiSend;

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
  } on CameraException catch (e) {
    logError(e.code, e.description);
  }

  ndiSend = NDISend("Phone 1");
  runApp(const CameraApp());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  ndiSend.stopSendFrames();
}

/// CameraApp is the Main Application.
class CameraApp extends StatelessWidget {
  /// Default Constructor
  const CameraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: APhoneApp(),
    );
  }
}
