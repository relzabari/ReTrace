import 'package:flutter/material.dart';

import 'data/auth_session.dart';
import 'features/auth/login_page.dart';
import 'features/setup/setup_page.dart';
import 'ui/app_design.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrototypeApp());
}

class PrototypeApp extends StatelessWidget {
  const PrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Exercise Tracker Prototype',
      theme: buildAppTheme(),
      locale: const Locale('he'),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthSession? _session;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await AuthSession.restore();
    if (mounted) {
      setState(() {
        _session = session;
        _restoring = false;
      });
    }
  }

  Future<void> _logout(bool allDevices) async {
    final revoked = await _session?.logout(allDevices: allDevices) ?? false;
    if (!mounted) return;
    setState(() => _session = null);
    if (!revoked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('יצאת מהמכשיר הזה, אך ביטול הסשן בשרת לא אושר. כשהחיבור זמין, התחבר שוב ובחר יציאה מכל המכשירים.'),
        duration: Duration(seconds: 12),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final session = _session;
    if (session == null) {
      return LoginPage(
        onAuthenticated: (value) => setState(() => _session = value),
      );
    }
    return SetupPage(session: session, onLogout: _logout);
  }
}
