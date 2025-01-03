import 'dart:io';

import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

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

  File? _chosenVideo;

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
            FilledButton.tonal(
              child: Text(_chosenVideo != null
                  ? "Replace Video..."
                  : "Choose Video..."),
              onPressed: () async {
                final chosenFile =
                    await ImagePicker().pickVideo(source: ImageSource.gallery);
                if (chosenFile == null) return;

                if (mounted) {
                  setState(() {
                    _chosenVideo = File(chosenFile.path);
                  });
                }
              },
            ),
            SizedBox(height: 10),
            if (_chosenVideo != null) ...[
              ElevatedButton(
                child: Text("Open Video Player"),
                onPressed: () => Amphitheatre.launch(
                  context,
                  controller: AmphitheatreController(
                    controller: VideoPlayerController.file(
                      _chosenVideo!,
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
                onPressed: () async {
                  final editedVideoPath = await AmphitheatreEditor.launch(
                    context,
                    controller: AmphitheatreController(
                      controller: VideoPlayerController.file(
                        _chosenVideo!,
                      ),
                    ),
                  );

                  if (editedVideoPath != null) {
                    setState(() {
                      _chosenVideo = File(editedVideoPath);
                    });
                  }
                },
              ),
            ]
          ],
        ),
      ),
    );
  }
}
