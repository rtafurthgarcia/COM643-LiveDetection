import 'package:cheetah_flutter/cheetah.dart';
import 'package:cheetah_flutter/cheetah_error.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

const String modelPath = "assets/cheetah_model.pv"; 

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Page()
      ),
    );
  }
}

class Page extends StatefulWidget {
  const Page({Key? key}) : super(key: key);

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  late Cheetah cheetahService;

  Future<void> setupTranscription() async {
    const apiKey = String.fromEnvironment('PICOVOICE_API_KEY', defaultValue: '');

    cheetahService = await Cheetah.create(apiKey, modelPath).whenComplete(() {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to setup the transcription service'),
          ),
        );
    });
  }

  void initState() {
    super.initState();
    setupTranscription();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            margin: const EdgeInsets.all(16.0),
            decoration:
                BoxDecoration(shape: BoxShape.circle),
            child: IconButton(
              iconSize: 64,
              icon: Icon(Icons.mic_off), 
              onPressed: null,
            ),
          ),
          Text(
            "AI Speech-to-text",
            style:  Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.blue),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}