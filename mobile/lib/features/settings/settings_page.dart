import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../data/auth_session.dart';
import '../../ui/app_design.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.session});

  final AuthSession session;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final ApiClient _api = ApiClient(widget.session);
  List<Map<String, dynamic>> _exercises = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _exerciseMembers = [];
  List<Map<String, dynamic>> _unlinkedParticipants = [];
  String? _selectedExerciseId;
  bool _loading = true;
  bool _loadingExerciseDetails = false;
  bool _busy = false;
  String? _error;

  Map<String, dynamic>? get _selectedExercise {
    final id = _selectedExerciseId;
    if (id == null) return null;
    for (final exercise in _exercises) {
      if (exercise['id'].toString() == id) return exercise;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({String? selectExerciseId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listExercises(),
        _api.listUsers(),
      ]);
      if (!mounted) return;
      final exercises = results[0];
      final requestedId = selectExerciseId ?? _selectedExerciseId;
      final selectedId =
          exercises.any((exercise) => exercise['id'].toString() == requestedId)
          ? requestedId
          : null;
      setState(() {
        _exercises = exercises;
        _users = results[1];
        _selectedExerciseId = selectedId;
      });
      await _loadExerciseDetails();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExerciseDetails() async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) {
      if (mounted) {
        setState(() {
          _exerciseMembers = [];
          _unlinkedParticipants = [];
        });
      }
      return;
    }
    setState(() {
      _loadingExerciseDetails = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listExerciseAccess(exerciseId),
        _api.listParticipants(exerciseId),
      ]);
      if (!mounted || exerciseId != _selectedExerciseId) return;
      setState(() {
        _exerciseMembers = results[0];
        _unlinkedParticipants = results[1]
            .where((participant) => participant['userId'] == null)
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted && exerciseId == _selectedExerciseId) {
        setState(() => _loadingExerciseDetails = false);
      }
    }
  }

  Future<String?> _askForExerciseName({String? initialValue}) async {
    final controller = TextEditingController(text: initialValue ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          initialValue == null ? 'יצירת תרגיל חדש' : 'שינוי שם התרגיל',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'שם התרגיל'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _createExercise() async {
    final name = await _askForExerciseName();
    if (name == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final exercise = await _api.createExercise(name);
      final id = exercise['id'].toString();
      await _api.startExercise(id);
      await _reload(selectExerciseId: id);
      _showSuccess('התרגיל נוצר והופעל בהצלחה.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameExercise() async {
    final exercise = _selectedExercise;
    if (exercise == null) return;
    final name = await _askForExerciseName(
      initialValue: exercise['name'].toString(),
    );
    if (name == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.renameExercise(_selectedExerciseId!, name);
      await _reload(selectExerciseId: _selectedExerciseId);
      _showSuccess('שם התרגיל עודכן.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeExercise() async {
    final exercise = _selectedExercise;
    if (exercise == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סגירת תרגיל'),
        content: Text(
          'לסגור את "${exercise['name']}"? לאחר הסגירה לא יהיה ניתן להצטרף אליו.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('סגור תרגיל'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.closeExercise(_selectedExerciseId!);
      await _reload(selectExerciseId: _selectedExerciseId);
      _showSuccess('התרגיל נסגר בהצלחה.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteExercise() async {
    final exercise = _selectedExercise;
    if (exercise == null) return;
    var acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('מחיקת תרגיל לצמיתות'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'התרגיל "${exercise['name']}" וכל המשתתפים, המסלולים והאירועים שלו יימחקו ללא אפשרות שחזור.',
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: acknowledged,
                onChanged: (value) =>
                    setDialogState(() => acknowledged = value ?? false),
                title: Text(
                  'אני מבין שהתרגיל "${exercise['name']}" יימחק לצמיתות במלואו.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: acknowledged
                  ? () => Navigator.pop(context, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('מחק לצמיתות'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.deleteExercise(_selectedExerciseId!);
      _selectedExerciseId = null;
      await _reload();
      _showSuccess('התרגיל נמחק לצמיתות.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExerciseAccess() async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) return;
    final emailController = TextEditingController();
    String? participantId;
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('הוספת גישה לתרגיל'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'כתובת מייל'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: participantId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'שיוך נתוני משתתף קודמים — לא חובה',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('ללא שיוך'),
                  ),
                  ..._unlinkedParticipants.map(
                    (participant) => DropdownMenuItem<String?>(
                      value: participant['id'].toString(),
                      child: Text(
                        participant['displayName'].toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => participantId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () {
                final email = emailController.text.trim();
                if (email.isNotEmpty) {
                  Navigator.pop(context, {
                    'email': email,
                    'participantId': participantId,
                  });
                }
              },
              child: const Text('הוסף גישה'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.grantExerciseAccess(
        exerciseId: exerciseId,
        email: result['email']!,
        participantId: result['participantId'],
      );
      await _loadExerciseDetails();
      _showSuccess('הגישה לתרגיל נוספה.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeExerciseAccess(Map<String, dynamic> member) async {
    final exerciseId = _selectedExerciseId;
    if (exerciseId == null) return;
    final confirmed = await _confirm(
      'הסרת גישה',
      'להסיר את הגישה של ${member['email']} מהתרגיל?',
      'הסר גישה',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.revokeExerciseAccess(exerciseId, member['id'].toString());
      await _loadExerciseDetails();
      _showSuccess('הגישה הוסרה.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addUser() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    var role = 'USER';
    String? validationError;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('הוספת משתמש'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'כתובת מייל'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'סיסמה זמנית — 8 תווים לפחות',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'סוג משתמש'),
                items: const [
                  DropdownMenuItem(value: 'USER', child: Text('USER')),
                  DropdownMenuItem(value: 'MANAGER', child: Text('MANAGER')),
                  DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => role = value);
                },
              ),
              if (validationError != null) ...[
                const SizedBox(height: 10),
                Text(
                  validationError!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () {
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (!email.contains('@') || password.length < 8) {
                  setDialogState(
                    () => validationError =
                        'יש להזין כתובת מייל וסיסמה באורך 8 תווים לפחות.',
                  );
                  return;
                }
                Navigator.pop(context, {
                  'email': email,
                  'password': password,
                  'role': role,
                });
              },
              child: const Text('הוסף משתמש'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    passwordController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.createUser(
        email: result['email']!,
        password: result['password']!,
        role: result['role']!,
      );
      await _reload(selectExerciseId: _selectedExerciseId);
      _showSuccess('המשתמש נוסף בהצלחה.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeUserRole(
    Map<String, dynamic> user,
    String newRole,
  ) async {
    final oldRole = user['role'].toString();
    if (oldRole == newRole) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.updateUserRole(user['id'].toString(), newRole);
      await _reload(selectExerciseId: _selectedExerciseId);
      _showSuccess('סוג המשתמש עודכן.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await _confirm(
      'מחיקת משתמש',
      'למחוק את המשתמש ${user['email']}? לא ניתן לבטל פעולה זו.',
      'מחק משתמש',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.deleteUser(user['id'].toString());
      await _reload(selectExerciseId: _selectedExerciseId);
      _showSuccess('המשתמש נמחק.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String message,
    String confirmLabel,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusLabel(Object? status) => switch (status?.toString()) {
    'DRAFT' => 'טיוטה',
    'ACTIVE' => 'פעיל',
    'ENDING' => 'בתהליך סגירה',
    'COMPLETED' => 'סגור',
    _ => status?.toString() ?? '',
  };

  Widget _errorBanner() => _error == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDEC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.danger),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!)),
            ],
          ),
        );

  Widget _exerciseManagementTab() {
    final exercise = _selectedExercise;
    final isActive = exercise?['status'] == 'ACTIVE';
    return RefreshIndicator(
      onRefresh: () => _reload(selectExerciseId: _selectedExerciseId),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            tint: const Color(0xFFF0FBF9),
            borderColor: const Color(0xFFB7E4DD),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(
                  'ניהול תרגילים',
                  icon: Icons.assignment_rounded,
                  color: AppColors.teal,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    '$_selectedExerciseId-${_exercises.map((item) => item['id']).join(',')}',
                  ),
                  initialValue: _selectedExerciseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'בחר תרגיל לניהול',
                    prefixIcon: Icon(Icons.list_alt_rounded),
                  ),
                  items: _exercises
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(
                            '${item['name']} — ${_statusLabel(item['status'])}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) async {
                          setState(() => _selectedExerciseId = value);
                          await _loadExerciseDetails();
                        },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _createExercise,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('תרגיל חדש'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || exercise == null
                          ? null
                          : _renameExercise,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('שנה שם'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || !isActive ? null : _closeExercise,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: const Text('סגור תרגיל'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || exercise == null
                          ? null
                          : _deleteExercise,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('מחק תרגיל'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (exercise != null) ...[
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: SectionTitle(
                          'גישה לתרגיל',
                          icon: Icons.group_add_rounded,
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _busy ? null : _addExerciseAccess,
                        tooltip: 'הוסף גישה',
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingExerciseDetails)
                    const Center(child: CircularProgressIndicator())
                  else if (_exerciseMembers.isEmpty)
                    const Text('אין משתמשים משויכים לתרגיל.')
                  else
                    ..._exerciseMembers.map(
                      (member) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline_rounded),
                        ),
                        title: Text(member['email'].toString()),
                        subtitle: Text(member['role'].toString()),
                        trailing:
                            member['id'].toString() == widget.session.user.id
                            ? const Tooltip(
                                message: 'לא ניתן להסיר את המשתמש הנוכחי',
                                child: Icon(Icons.shield_outlined),
                              )
                            : IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => _removeExerciseAccess(member),
                                tooltip: 'הסר גישה',
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                  color: AppColors.danger,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _userManagementTab() => RefreshIndicator(
    onRefresh: () => _reload(selectExerciseId: _selectedExerciseId),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: SectionTitle(
                      'ניהול משתמשים',
                      icon: Icons.manage_accounts_rounded,
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _busy ? null : _addUser,
                    tooltip: 'הוסף משתמש',
                    icon: const Icon(Icons.person_add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_users.isEmpty)
                const Text('לא נמצאו משתמשים.')
              else
                ..._users.map((user) {
                  final isCurrentUser =
                      user['id'].toString() == widget.session.user.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 0,
                    color: const Color(0xFFF7FAF8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            user['email'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: user['role'].toString(),
                                  decoration: const InputDecoration(
                                    labelText: 'סוג משתמש',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'USER',
                                      child: Text('USER'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'MANAGER',
                                      child: Text('MANAGER'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ADMIN',
                                      child: Text('ADMIN'),
                                    ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            _changeUserRole(user, value);
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                onPressed: _busy || isCurrentUser
                                    ? null
                                    : () => _deleteUser(user),
                                tooltip: isCurrentUser
                                    ? 'לא ניתן למחוק את המשתמש הנוכחי'
                                    : 'מחק משתמש',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 30),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.session.user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('הגדרות')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('מסך זה זמין למשתמש ADMIN בלבד.'),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('הגדרות'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFB7D2C8),
            tabs: [
              Tab(icon: Icon(Icons.assignment_rounded), text: 'ניהול תרגילים'),
              Tab(
                icon: Icon(Icons.manage_accounts_rounded),
                text: 'ניהול משתמשים',
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _errorBanner(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          children: [
                            _exerciseManagementTab(),
                            _userManagementTab(),
                          ],
                        ),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
