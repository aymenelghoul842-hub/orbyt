import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../profile.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_screen.dart';

/// First screen: gender, username and date of birth. After "Validate" you see the home page.
/// Orbyt is for adults only, so a date of birth under 18 is refused.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();
  String _gender = '';
  DateTime? _dob;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int _ageOf(DateTime d) {
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date of birth',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d != null) setState(() => _dob = d);
  }

  void _validate() {
    final name = _name.text.trim();
    String err = '';
    if (_gender.isEmpty) {
      err = 'Please select your gender.';
    } else if (name.length < 2) {
      err = 'Please enter a username (at least 2 characters).';
    } else if (_dob == null) {
      err = 'Please choose your date of birth.';
    } else if (_ageOf(_dob!) < 18) {
      err = 'Orbyt is only for people aged 18 and over.';
    }
    if (err.isNotEmpty) {
      setState(() => _error = err);
      return;
    }
    Profile.gender = _gender;
    Profile.username = name;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
  }

  Widget _chip(String label, IconData icon) {
    final selected = _gender == label;
    return ChoiceChip(
      avatar: Icon(icon,
          size: 18, color: selected ? AppColors.lime : AppColors.muted),
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        _gender = label;
        _error = '';
      }),
      showCheckmark: false,
      selectedColor: AppColors.lime.withOpacity(0.14),
      backgroundColor: Colors.white.withOpacity(0.06),
      side: BorderSide(
          color: selected
              ? AppColors.lime.withOpacity(0.5)
              : Colors.white.withOpacity(0.12)),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.lime : AppColors.text),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 16),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const OrbytLogo(size: 36),
                          const SizedBox(width: 10),
                          Text(appName,
                              style: display(
                                  size: 26,
                                  weight: FontWeight.w700,
                                  letterSpacing: -0.8)),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Text('Welcome! Tell us about you',
                            textAlign: TextAlign.center,
                            style: display(size: 22, weight: FontWeight.w700)),
                      ),
                      _label('I am'),
                      Wrap(spacing: 10, runSpacing: 6, children: [
                        _chip('Man', Icons.male_rounded),
                        _chip('Woman', Icons.female_rounded),
                        _chip('Other', Icons.person_rounded),
                      ]),
                      _label('Username'),
                      TextField(
                        controller: _name,
                        maxLength: 20,
                        onChanged: (_) => setState(() => _error = ''),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[\p{L}\p{N} _.\-]', unicode: true)),
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Your username',
                          hintStyle: const TextStyle(color: AppColors.muted),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      _label('Date of birth'),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickDate,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            const Icon(Icons.cake_rounded,
                                size: 20, color: AppColors.mint),
                            const SizedBox(width: 12),
                            Text(
                              _dob == null ? 'Choose your date of birth' : _fmt(_dob!),
                              style: TextStyle(
                                  color: _dob == null
                                      ? AppColors.muted
                                      : AppColors.text),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('Orbyt is for people aged 18 and over.',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.muted)),
                      if (_error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error,
                              style: const TextStyle(
                                  color: Color(0xFFFF6B6B),
                                  fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(height: 20),
                      GradientButton(
                          label: 'Validate',
                          icon: Icons.check_rounded,
                          onPressed: _validate),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
