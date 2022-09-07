import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:math' as math;

class FittedPlayer extends StatelessWidget {
  final VideoPlayerController videoController;
  const FittedPlayer({
    Key? key,
    required this.videoController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.black),
      child: FittedBox(
        alignment: Alignment.center,
        fit: BoxFit.contain,
        child: SizedBox(
          height: math.max(videoController.value.size.height, 10),
          width: math.max(videoController.value.size.width, 10),
          child: VideoPlayer(videoController),
        ),
      ),
    );
  }
}
