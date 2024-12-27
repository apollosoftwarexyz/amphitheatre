import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:video_player/video_player.dart';

import 'package:amphitheatre/amphitheatre.dart';

const kVideoUrl =
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4";

void main() {
  runApp(
    MaterialApp(
      home: const MyAppHome(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        AmphitheatreLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
    ),
  );
}

class MyAppHome extends StatefulWidget {
  const MyAppHome({super.key});

  @override
  State<MyAppHome> createState() => _MyAppHomeState();
}

class _MyAppHomeState extends State<MyAppHome> {
  late final AmphitheatreController controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ElevatedButton(
              child: Text("Open Video Player"),
              onPressed: () => Amphitheatre.launch(
                context,
                controller: AmphitheatreController(
                  controller: VideoPlayerController.networkUrl(
                    Uri.parse(kVideoUrl),
                  ),
                  info: AmphitheatreVideoInfo(
                    title: "Title of the video",
                    subtitle: "This is a subtitle.",
                    description:
                        "This is a long form description of the video. Lorem ipsum dolor sit amet.",
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text("Open Video Editor"),
              onPressed: () => AmphitheatreEditor.launch(
                context,
                controller: AmphitheatreController(
                  controller: VideoPlayerController.networkUrl(
                    Uri.parse(kVideoUrl),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
