import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/auth_controller.dart';
import '../../models/enums.dart';
import '../../widgets/ui.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _registering = false;
  bool _busy = false;
  String? _notice;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  UserRole _role = UserRole.passenger;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (_registering) {
        final needsConfirmation = await auth.signUp(
          email: _email.text,
          password: _password.text,
          fullName: _fullName.text,
          phone: _phone.text,
          role: _role,
        );
        if (needsConfirmation && mounted) {
          setState(() {
            _notice = 'Account created. Check your email to confirm, then sign in.';
            _registering = false;
          });
        }
      } else {
        await auth.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _notice = auth.error ?? e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = context.watch<AuthController>().error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/logo_with_title.png',
                    height: 104,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Book a tricycle or tuk-tuk/bao-bao in Mati City. Fixed fare before you ride.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 20),
                  InfoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Sign in')),
                            ButtonSegment(value: true, label: Text('Create account')),
                          ],
                          selected: {_registering},
                          onSelectionChanged: (s) => setState(() {
                            _registering = s.first;
                            _notice = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        if (_registering) ...[
                          const FieldLabel('Full name', required: true),
                          TextField(
                            controller: _fullName,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const FieldLabel('Mobile number', hint: 'Used for trip contact.'),
                          TextField(controller: _phone, keyboardType: TextInputType.phone),
                          const FieldLabel('I am a', required: true),
                          DropdownButtonFormField<UserRole>(
                            initialValue: _role,
                            items: const [
                              DropdownMenuItem(
                                value: UserRole.passenger,
                                child: Text('Passenger'),
                              ),
                              DropdownMenuItem(
                                value: UserRole.driver,
                                child: Text('Driver (needs verification before rides)'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _role = v ?? UserRole.passenger),
                          ),
                        ],
                        const FieldLabel('Email', required: true),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                        ),
                        const FieldLabel('Password', required: true),
                        TextField(controller: _password, obscureText: true),
                        const SizedBox(height: 16),
                        if (error != null && !_registering) ...[
                          ErrorBanner(error),
                          const SizedBox(height: 12),
                        ],
                        if (_notice != null) ...[
                          ErrorBanner(_notice!, tone: Tone.info),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_registering ? 'Create account' : 'Sign in'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Admin / LGU accounts are created by setting the profile role to "admin" in the database.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
