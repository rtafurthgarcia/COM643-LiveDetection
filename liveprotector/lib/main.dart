import 'package:cheetah_flutter/cheetah_error.dart';
import 'package:flutter/material.dart';
import 'package:liveprotector/cheetah_manager.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: Page()));
  }
}

class Page extends StatefulWidget {
  const Page({super.key});

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  final String accessKey = "50WHnPbczPX1+I+gdvYEO2btOBkTcwDYaWRY6v+ANjqs1YbbgyOigg==";
  final String modelPath = "assets/cheetah_model.pv";

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool isError = false;
  String errorMessage = "";

  bool isProcessing = false;
  String transcriptText = "";
  CheetahManager? _cheetahManager;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    setState(() {
      transcriptText = "";
    });

    initCheetah();
  }

  Future<void> initCheetah() async {
    final String modelPath = "assets/cheetah_model.pv";

    try {
      _cheetahManager = await CheetahManager.create(
        accessKey,
        modelPath,
        transcriptCallback,
        errorCallback,
      );
    } on CheetahActivationException {
      errorCallback(CheetahActivationException("AccessKey activation error."));
    } on CheetahActivationLimitException {
      errorCallback(
        CheetahActivationLimitException("AccessKey reached its device limit."),
      );
    } on CheetahActivationRefusedException {
      errorCallback(CheetahActivationRefusedException("AccessKey refused."));
    } on CheetahActivationThrottledException {
      errorCallback(
        CheetahActivationThrottledException("AccessKey has been throttled."),
      );
    } on CheetahException catch (ex) {
      errorCallback(ex);
    }
  }

  void transcriptCallback(String transcript) {
    bool shouldScroll =
        _controller.position.pixels == _controller.position.maxScrollExtent;

    setState(() {
      transcriptText = transcriptText + transcript;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (shouldScroll && !_controller.position.atEdge) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  void errorCallback(CheetahException error) {
    setState(() {
      isError = true;
      errorMessage = error.message!;
    });
  }

  Future<void> _startProcessing() async {
    if (isProcessing) {
      return;
    }

    try {
      await _cheetahManager!.startProcess();
      setState(() {
        transcriptText = "";
        isProcessing = true;
      });
    } on CheetahException catch (ex) {
      errorCallback(ex);
    }
  }

  Future<void> _stopProcessing() async {
    if (!isProcessing) {
      return;
    }

    try {
      await _cheetahManager!.stopProcess();
      setState(() {
        isProcessing = false;
      });
    } on CheetahException catch (ex) {
      errorCallback(ex);
    }
  }

  Color picoBlue = Color.fromRGBO(55, 125, 255, 1);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Live Detector: COM643'),
          backgroundColor: picoBlue,
        ),
        body: Column(
          children: [
            buildCheetahTextArea(context),
            buildErrorMessage(context),
            buildStartButton(context),
          ],
        ),
      ),
    );
  }

  buildStartButton(BuildContext context) {
    final ButtonStyle buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: picoBlue,
      shape: CircleBorder(),
      textStyle: TextStyle(color: Colors.white),
    );

    return Expanded(
      flex: 2,
      child: Container(
        child: SizedBox(
          width: 130,
          height: 130,
          child: ElevatedButton(
            style: buttonStyle,
            onPressed:
                isError
                    ? null
                    : isProcessing
                    ? _stopProcessing
                    : _startProcessing,
            child: Text(
              isProcessing ? "Stop" : "Start",
              style: TextStyle(fontSize: 30),
            ),
          ),
        ),
      ),
    );
  }

  buildCheetahTextArea(BuildContext context) {
    return Expanded(
      flex: 6,
      child: Container(
        alignment: Alignment.topCenter,
        color: Color(0xff25187e),
        margin: EdgeInsets.all(10),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.vertical,
          padding: EdgeInsets.all(10),
          physics: RangeMaintainingScrollPhysics(),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              transcriptText,
              textAlign: TextAlign.left,
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }

  buildErrorMessage(BuildContext context) {
    return Expanded(
      flex: isError ? 2 : 0,
      child: Container(
        alignment: Alignment.center,
        margin: EdgeInsets.only(left: 20, right: 20),
        padding: EdgeInsets.all(5),
        decoration:
            !isError
                ? null
                : BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(5),
                ),
        child:
            !isError
                ? null
                : Text(
                  errorMessage,
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
      ),
    );
  }
}
