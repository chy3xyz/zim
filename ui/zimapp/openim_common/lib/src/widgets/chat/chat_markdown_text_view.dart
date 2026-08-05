import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ChatMarkdownTextView extends StatefulWidget {
  const ChatMarkdownTextView({
    required Key key,
    this.isISend = false,
    required this.text,
    this.textScaleFactor = 1.0,
  }) : super(key: key);

  final bool isISend;
  final String text;
  final double textScaleFactor;

  @override
  ChatMarkdownTextViewState createState() => ChatMarkdownTextViewState();
}

class ChatMarkdownTextViewState extends State<ChatMarkdownTextView> with AutomaticKeepAliveClientMixin {
  late Future<String> _dataFuture;
  String? _lastText;
  String? _cachedText; // Cache the last text content

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    print('init state: ${widget.key}');
    _updateFuture(widget.text);
  }

  @override
  void didUpdateWidget(ChatMarkdownTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _lastText) {
      print('Text changed: old=$_lastText, new=${widget.text}');
      _updateFuture(widget.text);
    }
  }

  void _updateFuture(String text) {
    _lastText = text;
    _dataFuture = Future<String>.value(text).then((value) {
      print('Future completed for key: ${widget.key}, value: $value');
      setState(() {
        _cachedText = value; // Cache the completed content
      });
      return value;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Must call to support AutomaticKeepAliveClientMixin
    return FutureBuilder<String>(
      future: _dataFuture,
      initialData: _lastText,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        print(
            'FutureBuilder state: key=${widget.key}, connectionState=${snapshot.connectionState}, data=${snapshot.data}');
        // If cached content exists, display the cached MarkdownBody
        if (_cachedText != null) {
          return _buildMarkdownBody(_cachedText!);
        }
        // If the Future is complete, display the new content
        if (snapshot.connectionState == ConnectionState.done) {
          return _buildMarkdownBody(snapshot.data ?? '');
        }

        if (snapshot.connectionState == ConnectionState.waiting && snapshot.hasData) {
          return _buildMarkdownBody(snapshot.data ?? '');
        }
        // If no cache exists and the Future is not complete, display the loading indicator
        return const CircularProgressIndicator();
      },
    );
  }

  Widget _buildMarkdownBody(String data) {
    return SizedBox(
      width: 230.w,
      child: MarkdownBody(
        data: data,
        extensionSet: md.ExtensionSet.gitHubWeb,
        styleSheetTheme: MarkdownStyleSheetBaseTheme.platform,
        styleSheet: MarkdownStyleSheet(
          tableCellsDecoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
          ),
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.sp,
            backgroundColor: Colors.grey[200],
            wordSpacing: 0,
          ),
          tableColumnWidth: const IntrinsicColumnWidth(),
          codeblockDecoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          blockSpacing: 8.0,
          textScaleFactor: widget.textScaleFactor,
          p: TextStyle(
            fontSize: 16.sp,
            height: 1.5,
            overflow: TextOverflow.ellipsis,
          ),
          tableCellsPadding: const EdgeInsets.all(4.0),
        ),
        fitContent: true,
        softLineBreak: true,
        shrinkWrap: true,
        onTapLink: (text, href, title) async {
          if (href != null && await canLaunchUrlString(href)) {
            launchUrlString(href);
          }
        },
      ),
    );
  }
}
