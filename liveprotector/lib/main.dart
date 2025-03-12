import 'package:flutter/material.dart';
import 'package:liveprotector/llm_provider.dart';
import 'package:liveprotector/transcription_provider.dart';
import 'package:provider/provider.dart';

void main() {
  final String modelPath = "assets/cheetah_model.pv";

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create:
              (_) => TranscriptionProvider(
                modelPath: modelPath,
              ),
        ),
        ChangeNotifierProxyProvider<TranscriptionProvider, LLMProvider>(
          update: (context, transcriptionProvider, llmProvider) { 
            llmProvider!.verifyTranscript(transcriptionProvider.transcriptText);
            return llmProvider;
          },
          create: (BuildContext context) => LLMProvider(
            baseUrl: "http://10.26.74.55:1234/v1", 
            systemMessage: "Your function is to identify scams and phishing attempts happening per phone."
              "You are to protect employee from voice scammers, phishing attempts as voice phishing."
              "The scenario presented to you may be very diverse, and not all conversations have malicious content in them."
              "All the messages you receive are transcripts from conversations that happen in real time."
              "You will receive each chunk of conversation as jons's."
              "If you have to reason to believe one of the interlocutors in this conversation has poor intentions, as in if you are facing a scamming or phishing attempt,"
              "generate me the json output of the following: "
              "{"
              "'warning': true, "
              "'reason: 'your reason'"
              "}."
              "In 'reason', you have to put the reason why you think this is a scam. It has to be a short sentence as to why and what sort of attack it might be."
              "If you don't see anything dangerous or suspicious in the whole conversation, then just generate this instead"
              "{"
              "'warning': false, "
              "'reason: '"
              "}."
            ) 
        )
      ],
      child: MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: Page()));
  }
}

class Page extends StatefulWidget {
  const Page({super.key});

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final ScrollController _controller = ScrollController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(title: const Text('Live Detector: COM643')),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              buildRunningAnalysisCard(context),
              buildCheetahTextArea(context),
              buildErrorMessage(context),
              buildStartButton(context),
            ],
          ),
        ),
      ),
    );
  }

  buildRunningAnalysisCard(BuildContext context) {
    return Consumer2<TranscriptionProvider, LLMProvider>(
      builder: (context, transcriptionProvider, llmProvider, child) {
        return Card(
          color: llmProvider.warningTriggered ? 
            Theme.of(context).colorScheme.onError : 
            Theme.of(context).cardColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              llmProvider.warningTriggered ? ListTile(
                textColor: Theme.of(context).colorScheme.onErrorContainer,
                tileColor: Theme.of(context).colorScheme.onErrorContainer,
                leading: const Icon(Icons.warning_amber),
                title: Text('THIS CALL HAS BEEN IDENTIFIED AS DANGEROUS. HANG UP NOW'),
                subtitle: Text(llmProvider.warningMessage ?? 'NO REASON HAS BEEN GIVEN FOR THE DANGEROSITY OF THIS CALL.'),
              ) : ListTile(
                leading: Icon(transcriptionProvider.isProcessing ? Icons.shield : Icons.mic_off),
                title: Text(transcriptionProvider.isProcessing ? 'Your call is being analysed and protected in real-time.' : 'No running conversation.'),
                subtitle: Text(transcriptionProvider.isProcessing ? 'Your conversations are analysed on-premise only.' : 'No data is being collected right now.'),
              ),
              transcriptionProvider.isProcessing 
              && llmProvider.warningTriggered ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    child: const Text('END THE CALL NOW'),
                    onPressed: () => transcriptionProvider.stopProcessing()
                  ),
                ],
              ) : SizedBox.shrink(),
            ],
          ),
        );
      }
    );
  }

  buildStartButton(BuildContext context) {
    return Consumer<TranscriptionProvider>(
      builder: (context, provider, child) {
        return IconButton.outlined(
          color: Theme.of(context).primaryColor,
          iconSize: 32,
          onPressed: () => provider.exception != null
            ? null
            : provider.isProcessing
            ? provider.stopProcessing()
            : provider.startProcessing(),
          icon: Icon(
            provider.isProcessing ? Icons.call : Icons.call_end,
          ),
        );
      },
    );
  }

  buildCheetahTextArea(BuildContext context) {
    return Expanded(
      flex: 6,
      child: Container(
        alignment: Alignment.topCenter,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).primaryColor,
        ),
        margin: EdgeInsets.all(4.0),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.vertical,
          padding: EdgeInsets.all(10),
          physics: RangeMaintainingScrollPhysics(),
          child: Align(
            alignment: Alignment.topLeft,
            child: Consumer<TranscriptionProvider>(
              builder: (context, provider, child) {
                return Text(
                  provider.transcriptText,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  buildErrorMessage(BuildContext context) {
    return Selector<TranscriptionProvider, Exception?>(
      selector: (_, provider) => provider.exception,
      builder: (context, error, child) {
        return Expanded(
          flex: error != null ? 2 : 0,
          child: Container(
            alignment: Alignment.center,
            margin: EdgeInsets.only(left: 20, right: 20),
            padding: EdgeInsets.all(5),
            decoration:
                error == null
                    ? null
                    : BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(5),
                    ),
            child:
                error == null
                    ? null
                    : Text(
                      error.toString(),
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
          ),
        );
      },
    );
  }
}
