import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../application/beacon_controller.dart';
import '../audio/microphone.dart';
import '../data/content.dart';
import '../protocol/beacon_protocol.dart';

class BeaconApp extends StatefulWidget {
  final SharedPreferences preferences;
  final BeaconController? controller;
  const BeaconApp({super.key, required this.preferences, this.controller});
  @override
  State<BeaconApp> createState() => _BeaconAppState();
}

class _BeaconAppState extends State<BeaconApp> with WidgetsBindingObserver {
  late final controller =
      widget.controller ??
      BeaconController(MicrophoneCapture(), LocalContentRepository());
  late ThemeMode mode;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mode = ThemeMode.values.firstWhere(
      (e) => e.name == widget.preferences.getString('theme'),
      orElse: () => ThemeMode.system,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive && controller.active)) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  ThemeData theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff7139bd),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      brightness: brightness,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfffaf8fd)
          : const Color(0xff15121b),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      navigationBarTheme: const NavigationBarThemeData(height: 80),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 17, height: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Acoustic Beacon',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    home: BeaconHome(
      controller: controller,
      preferences: widget.preferences,
      mode: mode,
      changeTheme: (next) {
        setState(() => mode = next);
        widget.preferences.setString('theme', next.name);
      },
    ),
  );
}

class BeaconHome extends StatefulWidget {
  final BeaconController controller;
  final SharedPreferences preferences;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> changeTheme;
  const BeaconHome({
    super.key,
    required this.controller,
    required this.preferences,
    required this.mode,
    required this.changeTheme,
  });
  @override
  State<BeaconHome> createState() => _BeaconHomeState();
}

class _BeaconHomeState extends State<BeaconHome> {
  int tab = 0, onboardingPage = 0;
  late bool onboarded;
  final saved = <Map<String, dynamic>>[];
  String locationMessage =
      'Find participating locations using your location. This does not mean their beacons have been heard.';
  bool locating = false;
  List<BeaconLocation> locations = [];
  DateTime? announced;
  BeaconController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    onboarded = widget.preferences.getBool('onboarded') ?? false;
    for (final item
        in widget.preferences.getStringList('saved') ?? <String>[]) {
      try {
        saved.add(Map<String, dynamic>.from(jsonDecode(item) as Map));
      } catch (_) {
        /* Ignore damaged local entries. */
      }
    }
    c.addListener(changed);
  }

  void changed() {
    if (!mounted) {
      return;
    }
    if (c.lastDetection != null && announced != c.lastDetection) {
      announced = c.lastDetection;
      HapticFeedback.lightImpact();
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    super.dispose();
  }

  Future<void> save(BeaconContent item) async {
    if (saved.any((e) => e['id'] == item.id)) {
      return;
    }
    final entry = {
      'id': item.id,
      'merchant': item.merchant,
      'title': item.title,
      'description': item.description,
      'savedAt': DateTime.now().toIso8601String(),
      'expires': item.expires?.toIso8601String(),
      'redeemed': false,
    };
    final next = [...saved, entry];
    final success = await widget.preferences.setStringList(
      'saved',
      next.map(jsonEncode).toList(),
    );
    if (!mounted) {
      return;
    }
    if (success) {
      setState(() => saved.add(entry));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Saved for later' : 'Could not save. Please try again.',
        ),
      ),
    );
  }

  Future<void> findLocations() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services in your phone settings.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission is off. You can enable it in your phone settings.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      locations = await LocalLocationRepository().nearby(
        position.latitude,
        position.longitude,
      );
      locationMessage = locations.isEmpty
          ? 'Location discovery is not available yet. Participating places will appear here when the directory is ready.'
          : 'Nearby locations · found using location, not sound';
    } catch (e) {
      locationMessage = e.toString();
    }
    if (mounted) {
      setState(() => locating = false);
    }
  }

  Widget page(String eyebrow, String title, List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 24),
      ...children,
    ],
  );
  Widget message(IconData icon, String title, String body, {Widget? action}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(body, style: Theme.of(context).textTheme.bodyLarge),
              if (action != null) ...[const SizedBox(height: 24), action],
            ],
          ),
        ),
      );
  Widget offer(BeaconContent item, {String? savedAt}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.sensors),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.merchant,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(item.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(item.description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('You’re in control'),
                    content: const Text(
                      'This is a test beacon. There is no purchase, download, or external destination attached.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Get Deal'),
              ),
              if (savedAt == null)
                TextButton.icon(
                  onPressed: saved.any((e) => e['id'] == item.id)
                      ? null
                      : () => save(item),
                  icon: const Icon(Icons.bookmark_outline),
                  label: Text(
                    saved.any((e) => e['id'] == item.id) ? 'Saved' : 'Save',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            savedAt == null
                ? 'Heard and validated · ${c.lastDetection?.toLocal().toString().substring(0, 19) ?? ''}'
                : 'Saved ${savedAt.substring(0, 10)}',
          ),
          if (item.expires != null) Text('Expires ${item.expires!.toLocal()}'),
        ],
      ),
    ),
  );
  Widget detected() => page('Sound brings discovery', 'Detected', [
    if (c.error != null)
      message(
        Icons.info_outline,
        'Listening needs attention',
        c.error!,
        action: FilledButton(
          onPressed: c.busy ? null : c.start,
          child: const Text('Try again'),
        ),
      ),
    if (!c.active && c.error == null)
      message(
        Icons.sensors_off,
        'Listening is off',
        'Turn on listening to discover Acoustic Beacons while this app is open.',
        action: FilledButton(
          onPressed: c.busy ? null : c.start,
          child: Text(c.busy ? 'Requesting permission…' : 'Start listening'),
        ),
      ),
    if (c.content != null) ...[
      const Text(
        'Detected nearby',
        semanticsLabel: 'Acoustic beacon received and validated',
      ),
      offer(c.content!),
    ] else if (c.active) ...[
      const SizedBox(height: 24),
      const ListeningPulse(),
      const SizedBox(height: 32),
      Text(
        'Listening for Acoustic Beacons',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      const Text(
        'Offers and experiences will appear here when Acoustic Beacon detects a signal around you.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, height: 1.5),
      ),
    ],
    const SizedBox(height: 28),
    const Text(
      'Analyzed on your phone. You choose what happens next.',
      textAlign: TextAlign.center,
    ),
  ]);
  Widget nearYou() => page('Explore places', 'Near You', [
    message(
      Icons.place_outlined,
      'Nearby locations',
      locationMessage,
      action: FilledButton(
        onPressed: locating ? null : findLocations,
        child: Text(locating ? 'Finding your location…' : 'Use my location'),
      ),
    ),
    ...locations.map((e) => message(Icons.storefront, e.name, e.category)),
    const SizedBox(height: 16),
    const Text(
      'Places listed here are found using location. Only the Detected tab shows signals your phone has heard and validated.',
    ),
  ]);
  Widget savedPage() => page('Keep something good', 'Saved', [
    if (saved.isEmpty)
      message(
        Icons.bookmark_outline,
        'Worth keeping',
        'Save a detected offer and you’ll find it here.',
      ),
    ...saved.map(
      (e) => Column(
        children: [
          offer(
            BeaconContent(
              e['id'] as String,
              e['merchant'] as String,
              e['title'] as String,
              e['description'] as String,
              expires: e['expires'] == null
                  ? null
                  : DateTime.tryParse(e['expires'] as String),
            ),
            savedAt: e['savedAt'] as String,
          ),
          TextButton(
            onPressed: () async {
              final next = saved.where((item) => item != e).toList();
              final success = await widget.preferences.setStringList(
                'saved',
                next.map(jsonEncode).toList(),
              );
              if (success && mounted) {
                setState(() => saved.remove(e));
              }
            },
            child: const Text('Remove from saved'),
          ),
        ],
      ),
    ),
  ]);
  Widget settings() => page('Make it yours', 'Settings', [
    Card(
      child: SwitchListTile(
        title: const Text('Acoustic Beacon listening'),
        subtitle: const Text('While the app is open'),
        value: c.active,
        onChanged: c.busy ? null : (value) => value ? c.start() : c.stop(),
      ),
    ),
    const SizedBox(height: 20),
    const Text('PERMISSIONS'),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.mic_none),
      title: const Text('Microphone'),
      subtitle: Text(
        c.active
            ? 'In use for beacon signals'
            : 'Requested when listening starts',
      ),
      trailing: const Icon(Icons.open_in_new),
      onTap: Geolocator.openAppSettings,
    ),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_on_outlined),
      title: const Text('Location'),
      subtitle: const Text('Only requested for Near You'),
      onTap: Geolocator.openAppSettings,
    ),
    const SizedBox(height: 20),
    const Text('NOTIFICATIONS'),
    const ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('In-app discoveries only'),
      subtitle: Text('No push notifications in this prototype.'),
    ),
    const SizedBox(height: 20),
    const Text('APPEARANCE'),
    DropdownButton<ThemeMode>(
      isExpanded: true,
      value: widget.mode,
      items: ThemeMode.values
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text('${e.name[0].toUpperCase()}${e.name.substring(1)}'),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          widget.changeTheme(value);
        }
      },
    ),
    const SizedBox(height: 20),
    message(
      Icons.shield_outlined,
      'Designed with privacy in mind',
      'The microphone detects machine-readable acoustic signals. Analysis happens locally. Raw microphone recordings are not stored or uploaded. A signal cannot open links, make purchases, or execute actions.',
    ),
    ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('About Acoustic Beacon'),
      subtitle: const Text('Experimental prototype · 1.0.0'),
      onLongPress: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => DebugPage(controller: c)),
      ),
    ),
  ]);
  Widget onboarding() {
    const titles = [
      'Discover what’s around you.',
      'Designed with privacy in mind.',
      'You’re in control.',
    ];
    const bodies = [
      'Acoustic Beacon lets participating locations send useful information and offers through sound.',
      'Your phone analyzes beacon signals locally. Raw microphone recordings aren’t stored or uploaded.',
      'Nothing automatically opens, downloads, purchases, or redirects. You decide what to interact with.',
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: page(
              'Acoustic Beacon · ${onboardingPage + 1} of 3',
              titles[onboardingPage],
              [
                const SizedBox(height: 24),
                Icon(
                  [
                    Icons.sensors,
                    Icons.shield_outlined,
                    Icons.touch_app_outlined,
                  ][onboardingPage],
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 40),
                Text(
                  bodies[onboardingPage],
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 36),
                if (onboardingPage == 2)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Text(
                      'Next, allow microphone access to detect beacon signals while the app is open. Location permission is separate.',
                    ),
                  ),
                FilledButton(
                  onPressed: () async {
                    if (onboardingPage < 2) {
                      setState(() => onboardingPage++);
                      return;
                    }
                    await widget.preferences.setBool('onboarded', true);
                    if (!mounted) {
                      return;
                    }
                    setState(() => onboarded = true);
                    await c.start();
                  },
                  child: Text(
                    onboardingPage == 2 ? 'Enable listening' : 'Continue',
                  ),
                ),
                if (onboardingPage == 2)
                  TextButton(
                    onPressed: () {
                      widget.preferences.setBool('onboarded', true);
                      setState(() => onboarded = true);
                    },
                    child: const Text('Not now'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!onboarded) {
      return onboarding();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Acoustic Beacon',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: [detected, nearYou, savedPage, settings][tab](),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Detected'),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            label: 'Near You',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'Saved',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}

class ListeningPulse extends StatefulWidget {
  const ListeningPulse({super.key});
  @override
  State<ListeningPulse> createState() => _ListeningPulseState();
}

class _ListeningPulseState extends State<ListeningPulse>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.stop();
    } else {
      animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Listening for acoustic beacon signals',
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Center(
        child: Container(
          width: 150 + animation.value * 12,
          height: 150 + animation.value * 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .2),
              width: 2,
            ),
          ),
          child: Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.sensors,
                size: 44,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DebugPage extends StatefulWidget {
  final BeaconController controller;
  const DebugPage({super.key, required this.controller});
  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  late final zero = TextEditingController(
    text: widget.controller.config.zeroHz.toStringAsFixed(0),
  );
  late final one = TextEditingController(
    text: widget.controller.config.oneHz.toStringAsFixed(0),
  );
  late final threshold = TextEditingController(
    text: widget.controller.config.threshold.toString(),
  );
  late final timing = TextEditingController(
    text: widget.controller.config.symbolMs.toString(),
  );
  @override
  void dispose() {
    zero.dispose();
    one.dispose();
    threshold.dispose();
    timing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, d = c.detector.diagnostics;
      return Scaffold(
        appBar: AppBar(title: const Text('Beacon debug')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Diagnostic build D01',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SelectableText(
              'SESSION TOTALS — remain after Stop listening\n'
              'Active frequencies: ${c.config.zeroHz.toStringAsFixed(0)} / ${c.config.oneHz.toStringAsFixed(0)} Hz\n'
              'Active threshold: ${c.config.threshold} · symbol: ${c.config.symbolMs} ms\n'
              'Audio processed: ${(d.processedSamples / c.config.sampleRate).toStringAsFixed(1)} seconds\n'
              'Candidate blocks: ${d.candidateBlocks}\n'
              'Non-candidate blocks: ${d.quietBlocks}\n'
              'Accepted symbols: ${d.acceptedSymbols}\n'
              'Too-short bursts: ${d.shortBursts}\n'
              'Too-long bursts: ${d.longBursts}\n'
              'Preambles found: ${d.preamblesFound}\n'
              'Invalid headers: ${d.invalidHeaders}\n'
              'CRC/payload failures: ${d.crcFailures}\n'
              'CRC-valid frames: ${d.acceptedFrames}\n'
              'Last matching-frame count: ${d.matchingFrames}\n'
              'Validated beacon events: ${d.validatedBeacons}\n'
              'Peak tone amplitude: ${d.peakLevel.toStringAsFixed(5)}\n'
              'Recent burst lengths (ms): ${d.recentBurstMs.join(', ')}',
            ),
            const Text(
              'Starting listening or applying configuration resets these totals. No raw audio is saved.',
            ),
            const Divider(height: 32),
            SelectableText(
              'Microphone: ${c.active ? "ACTIVE" : "INACTIVE"}\nState: ${c.state.name}\nPCM stream requested: 48000 Hz / mono / 16 bit\nHardware rate: not exposed by capture plugin\nStrongest configured frequency: ${d.frequency.toStringAsFixed(0)} Hz\nSignal amplitude: ${d.level.toStringAsFixed(5)}\nThreshold: ${c.config.threshold}\nCandidate: ${d.candidate ? "YES" : "NO"}\nPreamble: ${d.preamble ? "FOUND" : "NOT FOUND"}\nPayload: ${d.payload}\nCRC: ${d.checksum}\nConfidence: ${(d.confidence * 100).toStringAsFixed(1)}%\nCRC-valid frames: ${d.acceptedFrames}\nRejected frames: ${d.rejectedFrames}\nLast validated detection: ${c.lastDetection ?? "None"}\n${c.error ?? ""}',
            ),
            const SizedBox(height: 24),
            const Text(
              'Experimental configuration. Applying stops listening. Match generator settings before restarting.',
            ),
            const SizedBox(height: 16),
            ...[
              (zero, 'Zero frequency (Hz)'),
              (one, 'One frequency (Hz)'),
              (threshold, 'Amplitude threshold'),
              (timing, 'Symbol duration (ms)'),
            ].map(
              (pair) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: pair.$1,
                  decoration: InputDecoration(labelText: pair.$2),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await c.configure(
                    BeaconConfig(
                      zeroHz: double.parse(zero.text),
                      oneHz: double.parse(one.text),
                      threshold: double.parse(threshold.text),
                      symbolMs: int.parse(timing.text),
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              child: const Text('Apply configuration'),
            ),
            TextButton(
              onPressed: () {
                zero.text = '4000';
                one.text = '5000';
              },
              child: const Text('Fill audible control frequencies'),
            ),
            FilledButton.tonal(
              onPressed: c.busy
                  ? null
                  : c.active
                  ? c.stop
                  : c.start,
              child: Text(c.active ? 'Stop listening' : 'Start listening'),
            ),
          ],
        ),
      );
    },
  );
}
