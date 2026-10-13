import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

const defaultBackend = 'https://jarvis-auhu.onrender.com';
const cyan = Color(0xFF58E7FF);
const bg = Color(0xFF030914);
const launcherChannel = MethodChannel('com.emzaro.jarvis/launcher');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JARVIS AI',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: cyan),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0A1B30),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0x6658E7FF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0x6658E7FF))),
      ),
    ),
    home: const JarvisHome(),
  );
}

class ChatLine {
  final String role, text;
  ChatLine(this.role, this.text);
  Map<String, dynamic> toJson() => {'role': role, 'content': text};
}

class LauncherApp {
  final String label;
  final String packageName;
  final String icon;
  LauncherApp({required this.label, required this.packageName, required this.icon});
  factory LauncherApp.fromMap(Map<dynamic, dynamic> map) => LauncherApp(
    label: map['label']?.toString() ?? 'App',
    packageName: map['packageName']?.toString() ?? '',
    icon: map['icon']?.toString() ?? '',
  );
}

class JarvisHome extends StatefulWidget {
  const JarvisHome({super.key});
  @override
  State<JarvisHome> createState() => _JarvisHomeState();
}

class _JarvisHomeState extends State<JarvisHome> with TickerProviderStateMixin {
  final input = TextEditingController();
  final appSearch = TextEditingController();
  final scroll = ScrollController();
  final tts = FlutterTts();
  final speech = stt.SpeechToText();
  final List<ChatLine> lines = [];
  final List<LauncherApp> apps = [];
  String backend = defaultBackend;
  String status = 'Connecting to secure AI backend…';
  String page = 'Home';
  String clock = '';
  bool busy = false, voiceReplies = true, listening = false, backendOK = false, loadingApps = false, overlayEnabled = false;
  Timer? clockTimer;
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _updateClock();
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    appSearch.addListener(() { if (mounted) setState(() {}); });
    launcherChannel.setMethodCallHandler((call) async {
      if (call.method == 'openAiFromOverlay' && mounted) {
        setState(() => page = 'AI');
        _jumpBottom();
      }
    });
    _init();
    _loadApps();
    _consumeOverlayLaunch();
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    if (mounted) setState(() => clock = '$h:$minute $ampm');
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    backend = p.getString('backend_url') ?? defaultBackend;
    voiceReplies = p.getBool('voice_replies') ?? true;
    final saved = p.getString('chat_history');
    if (saved != null) {
      try {
        for (final x in (jsonDecode(saved) as List).take(30)) {
          lines.add(ChatLine(x['role'].toString(), x['content'].toString()));
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
    await _testBackend();
  }

  Future<void> _consumeOverlayLaunch() async {
    try {
      final openAi = await launcherChannel.invokeMethod<bool>('consumeOpenAiIntent') ?? false;
      if (openAi && mounted) setState(() => page = 'AI');
    } catch (_) {}
  }

  Future<void> _toggleOverlay() async {
    try {
      final allowed = await launcherChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
      if (!allowed) {
        await launcherChannel.invokeMethod<bool>('requestOverlayPermission');
        _snack('Allow Display over other apps for JARVIS, return here, then tap Enable again.');
        return;
      }
      if (overlayEnabled) {
        await launcherChannel.invokeMethod<bool>('stopOverlay');
        if (mounted) setState(() => overlayEnabled = false);
        _snack('Floating JARVIS button stopped.');
      } else {
        await launcherChannel.invokeMethod<bool>('startOverlay');
        if (mounted) setState(() => overlayEnabled = true);
        _snack('Floating JARVIS button is active over other apps.');
      }
    } on PlatformException catch (e) {
      _snack('Overlay error: ${e.message ?? e.code}');
    } on MissingPluginException {
      _snack('Native overlay code is missing. Build and install the latest APK.');
    }
  }
  Future<void> _loadApps() async {
    if (loadingApps) return;
    setState(() => loadingApps = true);
    try {
      final raw = await launcherChannel.invokeMethod<List<dynamic>>('getApps');
      apps
        ..clear()
        ..addAll((raw ?? []).whereType<Map>().map(LauncherApp.fromMap).where((a) => a.packageName.isNotEmpty));
      apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    } on PlatformException catch (e) {
      _snack('Could not load installed apps: ${e.message ?? e.code}');
    } on MissingPluginException {
      _snack('App launching needs the latest JARVIS APK. Rebuild and install it.');
    } finally {
      if (mounted) setState(() => loadingApps = false);
    }
  }

  Future<void> _launchApp(LauncherApp app) async {
    try {
      await launcherChannel.invokeMethod<bool>('launchApp', {'packageName': app.packageName});
    } on PlatformException catch (e) {
      _snack('Could not open ${app.label}: ${e.message ?? e.code}');
    } on MissingPluginException {
      _snack('Install the latest JARVIS APK to launch apps.');
    }
  }

  Future<void> _testBackend() async {
    try {
      final r = await http.get(Uri.parse('${backend.replaceAll(RegExp(r'/+$'), '')}/health')).timeout(const Duration(seconds: 20));
      final data = jsonDecode(r.body);
      backendOK = r.statusCode == 200 && data is Map && data['ok'] == true;
      status = backendOK ? 'AI SYSTEM ONLINE' : 'Backend responded; check service status';
    } catch (_) {
      backendOK = false;
      status = 'AI backend offline';
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('chat_history', jsonEncode(lines.map((e) => e.toJson()).toList()));
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? input.text).trim();
    if (q.isEmpty || busy) return;
    input.clear();
    setState(() { lines.add(ChatLine('user', q)); lines.add(ChatLine('assistant', '…')); busy = true; });
    _jumpBottom();
    try {
      final history = lines.where((x) => x.text != '…').toList();
      final response = await http.post(
        Uri.parse('${backend.replaceAll(RegExp(r'/+$'), '')}/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'messages': [
          {'role':'system','content':'You are JARVIS, a concise, helpful personal AI assistant for Android. Give clear steps. Be honest about capabilities. Never claim to perform actions you did not perform.'},
          ...history.takeLast(14).map((x) => x.toJson()),
        ], 'temperature':0.65, 'max_tokens':850}),
      ).timeout(const Duration(seconds: 60));
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final err = data is Map ? (data['error'] ?? data['message'] ?? 'HTTP ${response.statusCode}') : 'HTTP ${response.statusCode}';
        throw Exception(err);
      }
      final answer = data['choices']?[0]?['message']?['content']?.toString() ?? 'No response received.';
      setState(() { lines.removeWhere((x) => x.text == '…'); lines.add(ChatLine('assistant', answer)); });
      if (voiceReplies) await tts.speak(answer.length > 1400 ? answer.substring(0,1400) : answer);
    } catch (e) {
      setState(() { lines.removeWhere((x) => x.text == '…'); lines.add(ChatLine('assistant', 'AI connection failed: $e')); });
    } finally {
      busy = false;
      await _saveHistory();
      if (mounted) setState(() {});
      _jumpBottom();
    }
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds:250), curve: Curves.easeOut);
    });
  }

  Future<void> _voice() async {
    final available = await speech.initialize(
      onStatus: (s) { if (mounted) setState(() => listening = s == 'listening'); },
      onError: (_) { if (mounted) setState(() => listening = false); },
    );
    if (!available) { _snack('Speech recognition is unavailable. Check microphone permission and internet.'); return; }
    if (listening) { await speech.stop(); setState(() => listening = false); return; }
    setState(() => listening = true);
    await speech.listen(
      onResult: (r) {
        final spoken = r.recognizedWords.trim();
        if (page == 'Apps') {
          appSearch.text = spoken;
          final command = spoken.toLowerCase();
          if (r.finalResult && (command.startsWith('open ') || command.startsWith('launch '))) {
            final requested = command.replaceFirst(RegExp(r'^(open|launch)\\s+'), '').trim();
            final matches = apps.where((a) => a.label.toLowerCase().contains(requested)).toList();
            final match = matches.isEmpty ? null : matches.first;
            if (match != null) {
              setState(() => listening = false);
              speech.stop();
              _launchApp(match);
              return;
            }
          }
        } else {
          input.text = spoken;
        }
        if (r.finalResult && mounted) setState(() => listening = false);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _settings() async {
    final controller = TextEditingController(text: backend);
    bool voiceOn = voiceReplies;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF08182B),
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('JARVIS SETTINGS', style: TextStyle(color: cyan, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Secure AI backend URL'),
          const SizedBox(height: 8),
          TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: defaultBackend)),
          const SizedBox(height: 8),
          const Text('Keep AI provider keys on the server, not in the app.', style: TextStyle(color: Colors.white60, fontSize: 12)),
          SwitchListTile(value: voiceOn, onChanged: (v) => update(() => voiceOn = v), title: const Text('Speak AI replies'), activeColor: cyan, contentPadding: EdgeInsets.zero),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () async { await _toggleOverlay(); if (ctx.mounted) update(() {}); },
            icon: Icon(overlayEnabled ? Icons.stop_circle_outlined : Icons.open_in_new_rounded),
            label: Text(overlayEnabled ? 'Stop floating JARVIS button' : 'Enable floating JARVIS button'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF19C76A), foregroundColor: const Color(0xFF04130A)),
          )),
          const Padding(padding: EdgeInsets.only(top: 6, bottom: 8), child: Text('The green J button stays above other apps. Android will ask you to allow Display over other apps the first time.', style: TextStyle(color: Colors.white60, fontSize: 12))),
          Row(children: [
            Expanded(child: FilledButton(onPressed: () async {
              final u = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
              if (!u.startsWith('https://')) { _snack('Enter a valid HTTPS backend URL.'); return; }
              final p = await SharedPreferences.getInstance();
              await p.setString('backend_url', u);
              await p.setBool('voice_replies', voiceOn);
              setState(() { backend = u; voiceReplies = voiceOn; });
              if (ctx.mounted) Navigator.pop(ctx);
              await _testBackend();
              _snack('Settings saved.');
            }, child: const Text('Save settings'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () async {
              backend = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
              await _testBackend();
              if (ctx.mounted) update(() {});
            }, child: const Text('Test backend'))),
          ]),
        ]),
      )),
    );
    controller.dispose();
  }

  @override
  void dispose() {
    input.dispose();
    appSearch.dispose();
    scroll.dispose();
    pulse.dispose();
    clockTimer?.cancel();
    speech.stop();
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0A2540), Color(0xFF030914), Color(0xFF080D20)]),
      ),
      child: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
          child: Row(children: [
            const Icon(Icons.blur_on_rounded, color: cyan, size: 30),
            const SizedBox(width: 8),
            const Text('J A R V I S', style: TextStyle(color: cyan, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 17)),
            const Spacer(),
            IconButton(onPressed: _settings, icon: const Icon(Icons.settings_outlined, color: Colors.white70)),
          ]),
        ),
        Expanded(child: _buildPage()),
        _bottomDock(),
      ])),
    ),
    floatingActionButton: FloatingActionButton(
      heroTag: 'jarvisFloatingAI',
      backgroundColor: const Color(0xFF19C76A),
      foregroundColor: const Color(0xFF04130A),
      tooltip: 'Activate JARVIS AI',
      onPressed: () {
        setState(() => page = 'AI');
        _jumpBottom();
      },
      child: const Icon(Icons.auto_awesome_rounded, size: 28),
    ),
  );

  Widget _buildPage() {
    if (page == 'Apps') return _appsPage();
    if (page == 'AI') return _chatPage();
    return _homePage();
  }

  Widget _homePage() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
    children: [
      const SizedBox(height: 14),
      Text(clock, textAlign: TextAlign.center, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300, letterSpacing: 1.5)),
      Text(DateTime.now().toLocal().toString().substring(0, 10), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      const SizedBox(height: 22),
      Center(child: AnimatedBuilder(animation: pulse, builder: (_, __) => Container(
        width: 126 + pulse.value * 8, height: 126 + pulse.value * 8,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: const RadialGradient(colors: [Color(0xFF1A7CA5), Color(0xFF07162B)]), border: Border.all(color: cyan.withOpacity(.75)), boxShadow: [BoxShadow(color: cyan.withOpacity(.15 + pulse.value*.2), blurRadius: 32, spreadRadius: 3)]),
        child: const Icon(Icons.auto_awesome, color: Color(0xFFCEFAFF), size: 52),
      ))),
      const SizedBox(height: 16),
      const Center(child: Text('AT YOUR SERVICE', style: TextStyle(color: cyan, letterSpacing: 3, fontSize: 11))),
      const SizedBox(height: 6),
      const Center(child: Text('Your personal AI system', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      const SizedBox(height: 8),
      Center(child: Text('● $status', style: TextStyle(color: backendOK ? const Color(0xFF8FFFD1) : Colors.orangeAccent, fontSize: 12))),
      const SizedBox(height: 20),
      _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ASK JARVIS', style: TextStyle(color: cyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: input, minLines: 1, maxLines: 2, onSubmitted: (_) { setState(() => page = 'AI'); _send(); }, decoration: const InputDecoration(hintText: 'Ask anything…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13)))),
          IconButton.filled(onPressed: () { setState(() => page = 'AI'); _send(); }, icon: const Icon(Icons.arrow_upward)),
          IconButton(onPressed: _voice, icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? Colors.redAccent : cyan)),
        ]),
      ])),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _shortcut(Icons.apps_rounded, 'All apps', () { setState(() => page = 'Apps'); _loadApps(); })),
        const SizedBox(width: 10),
        Expanded(child: _shortcut(Icons.chat_bubble_outline, 'Ask AI', () => setState(() => page = 'AI'))),
        const SizedBox(width: 10),
        Expanded(child: _shortcut(Icons.refresh_rounded, 'Reconnect', _testBackend)),
      ]),
      const SizedBox(height: 20),
      const Text('FAVOURITES', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1)),
      const SizedBox(height: 10),
      if (apps.isEmpty)
        _glass(child: Row(children: [const Expanded(child: Text('Loading installed apps…')), IconButton(onPressed: _loadApps, icon: const Icon(Icons.refresh, color: cyan))]))
      else
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: apps.take(8).length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: .78, mainAxisSpacing: 6),
          itemBuilder: (_, i) => _appTile(apps[i]),
        ),
    ],
  );

  Widget _appsPage() {
    final q = appSearch.text.trim().toLowerCase();
    final filtered = apps.where((a) => a.label.toLowerCase().contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(children: [
          const Expanded(child: Text('APP LIBRARY', style: TextStyle(color: cyan, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 17))),
          IconButton(onPressed: _loadApps, icon: const Icon(Icons.refresh, color: cyan), tooltip: 'Refresh apps'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: appSearch,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search, color: cyan), hintText: 'Search installed apps', suffixIcon: IconButton(onPressed: _voice, icon: const Icon(Icons.mic_none))),
        ),
      ),
      const SizedBox(height: 10),
      Expanded(child: loadingApps && apps.isEmpty
        ? const Center(child: CircularProgressIndicator(color: cyan))
        : filtered.isEmpty
          ? Center(child: Text(apps.isEmpty ? 'No apps found. Tap refresh.' : 'No matching apps.', style: const TextStyle(color: Colors.white60)))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
              itemCount: filtered.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: .78, mainAxisSpacing: 8, crossAxisSpacing: 4),
              itemBuilder: (_, i) => _appTile(filtered[i]),
            )),
    ]);
  }

  Widget _chatPage() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        const Expanded(child: Text('JARVIS AI', style: TextStyle(color: cyan, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 17))),
        TextButton(onPressed: () async { setState(() => lines.clear()); await _saveHistory(); }, child: const Text('Clear chat')),
      ]),
    ),
    Expanded(child: ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      children: [
        if (lines.isEmpty) const Padding(padding: EdgeInsets.all(28), child: Column(children: [Icon(Icons.auto_awesome, size: 42, color: cyan), SizedBox(height: 12), Text('Hello. How can I help?', style: TextStyle(fontSize: 18))])),
        ...lines.map((m) => Align(
          alignment: m.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(13),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
            decoration: BoxDecoration(color: m.role == 'user' ? const Color(0xFF103858) : const Color(0xFF0A1B30), border: Border.all(color: cyan.withOpacity(.18)), borderRadius: BorderRadius.circular(16)),
            child: Text(m.text),
          ),
        )),
      ],
    )),
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(children: [
        Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message JARVIS…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
        IconButton(onPressed: _voice, icon: Icon(listening ? Icons.mic : Icons.mic_none, color: cyan)),
        IconButton.filled(onPressed: busy ? null : () => _send(), icon: const Icon(Icons.send_rounded)),
      ]),
    ),
  ]);

  Widget _appTile(LauncherApp app) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => _launchApp(app),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 54, height: 54,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: const Color(0xFF10243A), borderRadius: BorderRadius.circular(16), border: Border.all(color: cyan.withOpacity(.15))),
          child: _appIcon(app),
        ),
        const SizedBox(height: 6),
        Text(app.label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: Colors.white)),
      ]),
    ),
  );

  Widget _appIcon(LauncherApp app) {
    if (app.icon.isNotEmpty) {
      try { return Image.memory(base64Decode(app.icon), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.android, color: cyan, size: 30)); }
      catch (_) {}
    }
    return const Icon(Icons.android, color: cyan, size: 30);
  }

  Widget _shortcut(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 6),
      decoration: BoxDecoration(color: const Color(0xAA10243A), borderRadius: BorderRadius.circular(16), border: Border.all(color: cyan.withOpacity(.18))),
      child: Column(children: [Icon(icon, color: cyan, size: 24), const SizedBox(height: 7), Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)]),
    ),
  );

  Widget _glass({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xCC163451), Color(0xBB071426)]), border: Border.all(color: cyan.withOpacity(.23)), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x2200AFFF), blurRadius: 22)]),
    child: child,
  );

  Widget _bottomDock() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
    decoration: BoxDecoration(color: const Color(0xEE061120), border: Border(top: BorderSide(color: cyan.withOpacity(.2)))),
    child: Row(children: [
      _nav(Icons.home_rounded, 'Home'),
      _nav(Icons.apps_rounded, 'Apps'),
      _nav(Icons.auto_awesome, 'AI'),
    ]),
  );

  Widget _nav(IconData icon, String label) => Expanded(
    child: TextButton.icon(
      onPressed: () {
        setState(() => page = label);
        if (label == 'Apps' && apps.isEmpty) _loadApps();
        if (label == 'AI') _jumpBottom();
      },
      icon: Icon(icon, size: 19, color: page == label ? cyan : Colors.white70),
      label: Text(label, style: TextStyle(fontSize: 11, color: page == label ? cyan : Colors.white70)),
    ),
  );
}

extension TakeLast<T> on List<T> {
  Iterable<T> takeLast(int n) => skip(length > n ? length - n : 0);
}
