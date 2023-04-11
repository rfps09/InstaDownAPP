import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

void main() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Plugin must be initialized before using
    await FlutterDownloader.initialize(
        debug: true, // optional: set to false to disable printing logs to console (default: true)
        ignoreSsl: false // option: set to false to disable working with http links (default: false)
    );
    runApp(const MyApp());
}

class InstaURL {
    final String url;
    final String type;

    const InstaURL({required this.url,required this.type});

    factory InstaURL.fromList(List<dynamic> urlAndType) {
        return InstaURL(url: urlAndType[0], type: urlAndType[1]);
    }
}

class InstaURLs {
    final List<InstaURL> urls;

    const InstaURLs({required this.urls});
}

class MyApp extends StatelessWidget {
    const MyApp({super.key});

    // This widget is the root of your application.
    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            title: 'InstaDown',
            theme: ThemeData(
                brightness: Brightness.light,
                primarySwatch: Colors.purple,
            ),
            darkTheme: ThemeData(
                brightness: Brightness.dark,
                primarySwatch: Colors.purple,
                appBarTheme: const AppBarTheme(
                    color: Colors.purple,
                ),
            ),
            themeMode: ThemeMode.system,
            home: const MyHomePage(title: 'InstaDown'),
        );
    }
}

class MyHomePage extends StatefulWidget {
    const MyHomePage({super.key, required this.title});

    final String title;

    @override
    State<MyHomePage> createState() => _MyHomePageState();
}

Future<InstaURLs> getURLs(String url) async {
    List<InstaURL> urls = [];

    final httpRequest = await http.get(Uri.parse(url));

    if(httpRequest.statusCode == 200) {
        RegExp imgExp = RegExp(r'\"url\"\:\"https\:\\\/\\\/scontent([^\"]|[.])*\"?');
        Iterable<RegExpMatch> imgMatches = imgExp.allMatches(httpRequest.body);

        for (final m in imgMatches) {
            String link = m[0]!.substring(7,m[0]!.length-1).replaceAll(RegExp(r'\\\/'), '/').replaceAll(RegExp(r'\\u0025'), '%');
            urls.add(InstaURL(url: link, type: 'image'));
        }

        RegExp vidExp = RegExp(r'\"contentUrl\"\:\"([^\"]|[.])*\"?');
        Iterable<RegExpMatch> vidMatches = vidExp.allMatches(httpRequest.body);

        for (final m in vidMatches) {
            String link = m[0]!.substring(14).replaceAll(RegExp(r'\\\/'), '/').replaceAll(RegExp(r'\\u0025'), '%');
            urls.add(InstaURL(url: link, type: 'video'));
        }

        return InstaURLs(urls: urls);
    } else {
        throw Exception('Failed to load');
    }
}

class _MyHomePageState extends State<MyHomePage> {
    late Future<InstaURLs>? midiaURLs = null;
    final TextEditingController _textController = TextEditingController();
    List<bool> onAndOffButton = [];
    List<dynamic> idxToID = [];
    List<Widget> children = [];
    int midiaIdx = 0;
    int midiaMaxIdx = 0;

    VideoPlayerController initVideo(String url) {
        return VideoPlayerController.network(url);
    }

    void download(String url, int idx) async {
        var statusNotification = await Permission.notification.request();
        var statusAnd13orAbove = await Permission.photos.request();
        var statusAnd12orBelow = await Permission.storage.request();
        if((statusAnd13orAbove.isGranted) || (statusAnd12orBelow.isGranted)) {
            RegExp exp = RegExp(r'([^\/]|[.])*\?');
            String filename = exp.firstMatch(url)![0]!.replaceAll(RegExp(r'\?'), "");
            Directory? dir = await getExternalStorageDirectory();
            var taskID = await FlutterDownloader.enqueue(
                url: url,
                headers: {},
                savedDir: dir!.path,
                fileName: filename,
                showNotification: true,
                openFileFromNotification: true,
                saveInPublicStorage: true,
            );

            idxToID[idx] = taskID;
        }
    }

    final ReceivePort _port = ReceivePort();

    @override
    void initState() {
        super.initState();

        _bindBackgroundIsolate();

        FlutterDownloader.registerCallback(downloadCallback, step: 1);
    }

    @override
    void dispose() {
        _unbindBackgroundIsolate();
        super.dispose();
    }

    void _bindBackgroundIsolate() {
        final isSuccess = IsolateNameServer.registerPortWithName(
            _port.sendPort,
            'downloader_send_port',
        );
        if (!isSuccess) {
            _unbindBackgroundIsolate();
            _bindBackgroundIsolate();
            return;
        }
        _port.listen((dynamic data) {
            final taskId = (data as List<dynamic>)[0] as String;
            final status = DownloadTaskStatus(data[1] as int);
            final progress = data[2] as int;

            for(int i=0; i<idxToID.length; i++) {
                if(idxToID[i] != null && idxToID[i] == taskId && status == DownloadTaskStatus.complete) {
                    setState(() {
                        onAndOffButton[i] = false;
                        children = [];
                    });
                }
            }
        });
    }

    void _unbindBackgroundIsolate() {
        IsolateNameServer.removePortNameMapping('downloader_send_port');
    }

    @pragma('vm:entry-point')
    static void downloadCallback(String id, DownloadTaskStatus status, int progress) {
        IsolateNameServer.lookupPortByName('downloader_send_port')?.send([id, status.value, progress]);
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                // Here we take the value from the MyHomePage object that was created by
                // the App.build method, and use it to set our appbar title.
                title: Text(widget.title),
            ),
            body: SingleChildScrollView(
                child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                            TextField(
                                controller: _textController,
                                decoration: const InputDecoration(hintText: 'URL do Instagram'),
                            ),
                            ElevatedButton(
                                onPressed: () {
                                    setState(() {
                                        midiaURLs = getURLs(_textController.text);
                                        onAndOffButton = [];
                                        idxToID = [];
                                        children = [];
                                    });
                                },
                                child: const Text('Procurar'),
                            ),
                            const SizedBox(
                                height: 50,
                            ),
                            FutureBuilder<InstaURLs>(
                                future: midiaURLs,
                                builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                        if(children.isEmpty) {
                                            bool fillList = false;
                                            if(onAndOffButton.isEmpty) {
                                                fillList = true;
                                            }
                                            int nextIdx = 0;
                                            for(InstaURL midia in snapshot.data!.urls) {
                                                List<Widget> child = [];
                                                if(fillList) {
                                                    onAndOffButton.add(true);
                                                    idxToID.add(null);
                                                }
                                                int idx = nextIdx;
                                                nextIdx++;
                                                if (midia.type == 'image') {
                                                    child.add(
                                                        SizedBox(
                                                            width: 290,
                                                            height: 290,
                                                            child: Image.network(midia.url)
                                                        )
                                                    );
                                                }
                                                else {
                                                    late VideoPlayerController _controller = initVideo(midia.url);
                                                    child.add(
                                                        FutureBuilder(
                                                            future: _controller.initialize(),
                                                            builder: (context, snapshot) {
                                                                if (snapshot.connectionState == ConnectionState.done) {
                                                                    return SizedBox(
                                                                        width: 290,
                                                                        height: 290,
                                                                        child: Center(
                                                                            child: InkWell(
                                                                                onTap: () {
                                                                                    if (_controller.value.isPlaying) {
                                                                                        _controller.pause();
                                                                                    } else {
                                                                                        _controller.play();
                                                                                    }
                                                                                },
                                                                                child: AspectRatio(
                                                                                    aspectRatio:
                                                                                    _controller.value.aspectRatio,
                                                                                    child: VideoPlayer(_controller),
                                                                                ),
                                                                            ),
                                                                        )
                                                                    );
                                                                }
                                                                else {
                                                                    // If the VideoPlayerController is still initializing, show a
                                                                    // loading spinner.
                                                                    return const Center(
                                                                    child: CircularProgressIndicator(),
                                                                    );
                                                                }
                                                            },
                                                        )
                                                    );
                                                }
                                                child.add(Text('Tipo da midia: ${midia.type}'));
                                                child.add(
                                                    ElevatedButton(
                                                        onPressed: onAndOffButton[idx] ? () {
                                                            download(midia.url, idx);
                                                            if(!onAndOffButton[idx]) {
                                                                setState(() {
                                                                    onAndOffButton[idx] = false;
                                                                });
                                                            }
                                                        }:null,
                                                        child: Text('Download'),
                                                    )
                                                );
                                                children.add(
                                                    Column(
                                                        children: child,
                                                    )
                                                );
                                            }
                                            midiaMaxIdx = nextIdx-1;
                                        }
                                        return Center(
                                            child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: <Widget> [
                                                    IconButton(
                                                        icon: const Icon(
                                                            Icons.navigate_before,
                                                        ),
                                                        tooltip: 'Voltar',
                                                        style: TextButton.styleFrom(
                                                            minimumSize: const Size(40, 40),
                                                            padding: const EdgeInsets.all(0),
                                                        ),
                                                        onPressed: () {
                                                            if(midiaIdx > 0) {
                                                                setState(() {
                                                                  midiaIdx--;
                                                                });
                                                            }
                                                        },
                                                    ),
                                                    children.elementAt(midiaIdx),
                                                    IconButton(
                                                        icon: const Icon(
                                                            Icons.navigate_next,
                                                        ),
                                                        tooltip: 'Avançar',
                                                        style: TextButton.styleFrom(
                                                            minimumSize: const Size(40, 40),
                                                            padding: const EdgeInsets.all(0),
                                                        ),
                                                        onPressed: () {
                                                            if(midiaIdx < midiaMaxIdx) {
                                                                setState(() {
                                                                    midiaIdx++;
                                                                });
                                                            }
                                                        },
                                                    ),
                                                ],
                                            )
                                        );
                                    }
                                    // By default, show a loading spinner.
                                    if(_textController.text != '') {
                                        return const Center(
                                            child: CircularProgressIndicator(),
                                        );
                                    }
                                    return const Text('Insira a URL de uma postagem do instagram');
                                },
                            ),
                        ],
                    ),
                ),
            )
        );
    }
}
