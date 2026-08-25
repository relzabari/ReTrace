import 'package:flutter/material.dart';

import '../../data/auth_session.dart';
import '../../ui/app_design.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onAuthenticated});

  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'יש להזין מייל וסיסמה.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await AuthSession.login(
        email: _email.text,
        password: _password.text,
      );
      widget.onAuthenticated(session);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    String? dialogError;
    bool sending = false;
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: !sending,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_rounded,
              size: 38, color: AppColors.teal),
          title: const Text('איפוס סיסמה'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'הזן את כתובת המייל. אם היא רשומה במערכת, יישלח אליה קישור מאובטח להגדרת סיסמה חדשה.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                enabled: !sending,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'כתובת מייל',
                    prefixIcon: Icon(Icons.alternate_email_rounded)),
              ),
              if (dialogError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(dialogError!,
                      style: const TextStyle(color: AppColors.danger)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed:
                    sending ? null : () => Navigator.pop(dialogContext, false),
                child: const Text('ביטול')),
            FilledButton.icon(
              onPressed: sending
                  ? null
                  : () async {
                      final email = controller.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        setDialogState(
                            () => dialogError = 'יש להזין כתובת מייל תקינה.');
                        return;
                      }
                      setDialogState(() {
                        sending = true;
                        dialogError = null;
                      });
                      try {
                        await AuthSession.requestPasswordReset(email: email);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            sending = false;
                            dialogError = error.toString();
                          });
                        }
                      }
                    },
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(sending ? 'שולח...' : 'שלח קישור'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('אם כתובת המייל רשומה במערכת, קישור לאיפוס נשלח אליה.')),
      );
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                const SizedBox(height: 10),
                const Text(
                  'ReTrace',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: AppColors.forestDark),
                ),
                const Text(
                  'מערכת ניהול ומעקב תרגילים',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.teal, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 28),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle('כניסה למערכת',
                          icon: Icons.lock_open_rounded),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'כתובת מייל',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        onSubmitted: _busy ? null : (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'סיסמה',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GradientActionButton(
                        onPressed: _busy ? null : _login,
                        icon: Icons.login_rounded,
                        label: _busy ? 'מתחבר...' : 'כניסה',
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : _forgotPassword,
                  icon: const Icon(Icons.help_outline_rounded),
                  label: const Text('שכחתי סיסמה'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
