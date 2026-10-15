import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../ui/app_design.dart';

class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'אודות',
        icon: const Icon(Icons.info_outline_rounded),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AboutPage()),
        ),
      );
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.loadPackageInfo});

  final Future<PackageInfo> Function()? loadPackageInfo;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late Future<PackageInfo> _packageInfo;

  Future<PackageInfo> _load() async => widget.loadPackageInfo != null
      ? await widget.loadPackageInfo!()
      : await PackageInfo.fromPlatform();

  @override
  void initState() {
    super.initState();
    _packageInfo = _load();
  }

  Widget _infoRow(String label, String value) => ListTile(
        title: Text(label),
        trailing: SelectableText(
          value.isEmpty ? 'לא זמין' : value,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      );

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('אודות')),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.route_rounded,
                        size: 64, color: AppColors.forest),
                    const SizedBox(height: 12),
                    const Text(
                      'ReTrace',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text('מערכת ניהול ומעקב תרגילים',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return Column(
                            children: [
                              const Text('לא ניתן לטעון את פרטי הגרסה.'),
                              TextButton(
                                onPressed: () => setState(() => _packageInfo = _load()),
                                child: const Text('נסה שוב'),
                              ),
                            ],
                          );
                        }
                        final info = snapshot.data!;
                        return AppCard(
                          child: Column(
                            children: [
                              _infoRow('גרסה', info.version),
                              const Divider(),
                              _infoRow('מספר בנייה', info.buildNumber),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
