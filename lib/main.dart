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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JARVIS AI Launcher',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: cyan),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF0A1B30),
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

class JarvisHome extends StatefulWidget {
  const JarvisHome({super.key});
  @override
  State<JarvisHome> createState() => _JarvisHomeState();
}

class _JarvisHomeState extends State<JarvisHome> with TickerProviderStateMixin {
  final input = TextEditingController();
  final scroll = ScrollController();
  final tts = FlutterTts();
  final speech = stt.SpeechToText();
  final List<ChatLine> lines = [];
  String backend = defaultBackend;
  String status = 'Connecting to secure AI backend…';
  String page = 'Home';
  bool busy = false, voiceReplies = true, listening = false, backendOK = false;
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void initState() { super.initState(); _init(); }
  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    backend = p.getString('backend_url') ?? defaultBackend;
    voiceReplies = p.getBool('voice_replies') ?? true;
    final saved = p.getString('chat_history');
    if (saved != null) {
      try { for (final x in (jsonDecode(saved) as List).take(30)) { lines.add(ChatLine(x['role'], x['content'])); } } catch (_) {}
    }
    if (mounted) setState(() {});
    await _testBackend();
  }
  Future<void> _testBackend() async {
    try {
      final r = await http.get(Uri.parse('${backend.replaceAll(RegExp(r'/+$'), '')}/health')).timeout(const Duration(seconds: 20));
      final data = jsonDecode(r.body);
      backendOK = r.statusCode == 200 && data['ok'] == true;
      status = backendOK ? 'Secure AI backend online' : 'Backend responded; check service status';
    } catch (_) { backendOK = false; status = 'Backend not reachable yet'; }
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
      busy = false; await _saveHistory(); if (mounted) setState(() {}); _jumpBottom();
    }
  }
  void _jumpBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds:250), curve: Curves.easeOut); }); }
  Future<void> _voice() async {
    final available = await speech.initialize(onStatus: (s) { if (mounted) setState(() => listening = s == 'listening'); }, onError: (_) { if (mounted) setState(() => listening = false); });
    if (!available) { _snack('Speech recognition is unavailable. Check microphone permission and internet.'); return; }
    if (listening) { await speech.stop(); setState(() => listening = false); return; }
    setState(() => listening = true);
    await speech.listen(onResult: (r) { input.text = r.recognizedWords; if (r.finalResult) setState(() => listening = false); }, listenFor: const Duration(seconds: 30), pauseFor: const Duration(seconds: 4));
  }
  void _snack(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  Future<void> _settings() async {
    final controller = TextEditingController(text: backend);
    bool voiceOn = voiceReplies;
    await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF08182B), builder: (ctx) => StatefulBuilder(builder: (ctx, update) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('JARVIS SETTINGS', style: TextStyle(color: cyan, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Secure AI backend URL'),
        const SizedBox(height: 8),
        TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: defaultBackend)),
        const SizedBox(height: 8),
        const Text('Groq key remains on the server. Do not paste it into the app.', style: TextStyle(color: Colors.white60, fontSize: 12)),
        SwitchListTile(value: voiceOn, onChanged: (v) => update(() => voiceOn = v), title: const Text('Speak AI replies'), activeColor: cyan, contentPadding: EdgeInsets.zero),
        Row(children: [
          Expanded(child: FilledButton(onPressed: () async {
            final u = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
            if (!u.startsWith('https://')) { _snack('Enter a valid HTTPS backend URL.'); return; }
            final p = await SharedPreferences.getInstance(); await p.setString('backend_url', u); await p.setBool('voice_replies', voiceOn);
            setState(() { backend = u; voiceReplies = voiceOn; }); if (ctx.mounted) Navigator.pop(ctx); await _testBackend(); _snack('Settings saved.');
          }, child: const Text('Save settings'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () async { backend = controller.text.trim().replaceAll(RegExp(r'/+$'), ''); await _testBackend(); if (ctx.mounted) update(() {}); }, child: const Text('Test backend'))),
        ]),
      ]),
    )));
  }
  @override
  void dispose() { input.dispose(); scroll.dispose(); pulse.dispose(); speech.stop(); tts.stop(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('◉ J A R V I S', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)), actions: [IconButton(onPressed: _settings, icon: const Icon(Icons.settings_outlined))]),
    body: SafeArea(child: Column(children: [
      Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 6, 16, 14), children: [
        if (page == 'Home') ...[
          const SizedBox(height: 8),
          Center(child: AnimatedBuilder(animation: pulse, builder: (_, __) => Container(width: 150 + pulse.value * 8, height: 150 + pulse.value * 8, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const RadialGradient(colors: [Color(0xFF16618C), Color(0xFF06172B)]), border: Border.all(color: cyan.withOpacity(.8)), boxShadow: [BoxShadow(color: cyan.withOpacity(.15 + pulse.value*.2), blurRadius: 32, spreadRadius: 3)]), child: const Icon(Icons.auto_awesome, color: Color(0xFFCEFAFF), size: 58)))),
          const SizedBox(height: 18),
          const Center(child: Text('AT YOUR SERVICE', style: TextStyle(color: cyan, letterSpacing: 3, fontSize: 12))),
          const SizedBox(height: 6),
          const Center(child: Text('Your personal AI system', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          Center(child: Text('● $status', style: TextStyle(color: backendOK ? const Color(0xFF8FFFD1) : Colors.orangeAccent, fontSize: 12))),
          const SizedBox(height: 18),
          _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TALK TO JARVIS', style: TextStyle(color: cyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Ask anything…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13)))),
              const SizedBox(width: 7),
              IconButton.filled(onPressed: busy ? null : () => _send(), icon: const Icon(Icons.arrow_upward)),
              IconButton(onPressed: _voice, icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? Colors.redAccent : cyan)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 7, runSpacing: 7, children: [
              _chip('Daily briefing', () => _send('Give me a concise briefing for today')),
              _chip('Teach me', () => _send('Explain something new to me')),
              _chip('Productivity', () => _send('Give me five ideas to be productive')),
            ]),
          ])),
          const SizedBox(height: 12),
          _glass(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('QUICK TOOLS', style: TextStyle(color: cyan, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _tool(Icons.apps, 'App library', () => _snack('Android app-launching integration is not yet ported to this Flutter build.')),
              _tool(Icons.phone, 'Calls', () => _snack('Contact-picker integration is not yet ported to this Flutter build.')),
              _tool(Icons.message, 'WhatsApp', () => _snack('WhatsApp draft integration is not yet ported to this Flutter build.')),
              _tool(Icons.notifications_active, 'Reminders', () => _snack('Reminder notifications integration is not yet ported to this Flutter build.')),
              _tool(Icons.monitor_heart, 'Trading signals', () => _snack('Trading signal screen-scanning integration is not yet ported to this Flutter build.')),
              _tool(Icons.refresh, 'Reconnect AI', _testBackend),
            ]),
          ])),
        ] else ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('RECENT CONVERSATION', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)), TextButton(onPressed: () async { setState(() => lines.clear()); await _saveHistory(); }, child: const Text('Clear'))]),
          if (lines.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Your conversations will appear here.', textAlign: TextAlign.center)),
          ...lines.map((m) => Align(alignment: m.role == 'user' ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(13), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84), decoration: BoxDecoration(color: m.role == 'user' ? const Color(0xFF103858) : const Color(0xFF0A1B30), border: Border.all(color: cyan.withOpacity(.18)), borderRadius: BorderRadius.circular(16)), child: Text(m.text)))),
        ],
      ])),
      Container(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), decoration: BoxDecoration(color: const Color(0xEE061120), border: Border(top: BorderSide(color: cyan.withOpacity(.2)))), child: Row(children: [
        _nav(Icons.home_rounded, 'Home'), _nav(Icons.chat_bubble_outline, 'Chat'), _nav(Icons.settings_outlined, 'Settings'),
      ])),
    ])),
  );
  Widget _glass({required Widget child}) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xCC163451), Color(0xBB071426)]), border: Border.all(color: cyan.withOpacity(.23)), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x2200AFFF), blurRadius: 22)]), child: child);
  Widget _chip(String text, VoidCallback onTap) => ActionChip(label: Text(text, style: const TextStyle(fontSize: 12)), onPressed: onTap, backgroundColor: const Color(0xFF102A43), side: BorderSide(color: cyan.withOpacity(.2)));
  Widget _tool(IconData icon, String label, VoidCallback onTap) => SizedBox(width: 98, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [Icon(icon, color: cyan, size: 25), const SizedBox(height: 5), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))]))));
  Widget _nav(IconData icon, String label) => Expanded(child: TextButton.icon(onPressed: () { if (label == 'Settings') { _settings(); } else { setState(() => page = label); if (label == 'Chat') _jumpBottom(); } }, icon: Icon(icon, size: 18, color: page == label ? cyan : Colors.white70), label: Text(label, style: TextStyle(fontSize: 11, color: page == label ? cyan : Colors.white70))));
}

extension TakeLast<T> on List<T> {
  Iterable<T> takeLast(int n) => skip(length > n ? length - n : 0);
}
