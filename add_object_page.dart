import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AddObjectPage extends StatefulWidget {
  const AddObjectPage({super.key});

  @override
  State<AddObjectPage> createState() => _AddObjectPageState();
}

class _AddObjectPageState extends State<AddObjectPage> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _mainTextController = TextEditingController();
  final _linkController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _consentChecked = false;
  bool _sending = false;

static const String _formUrl =
    'https://docs.google.com/forms/d/e/1FAIpQLScYkeYOhmpO7Lc-eu-5PJTKFd3aj4r8_7jr6IadgIATWpdwEQ/formResponse';

  static const String _titleEntry = 'entry.370589101';
  static const String _descriptionEntry = 'entry.1769348752';
  static const String _linkEntry = 'entry.533152444';
  static const String _nameEntry = 'entry.979446873';
  static const String _emailEntry = 'entry.752972680';

  @override
  void dispose() {
    _titleController.dispose();
    _mainTextController.dispose();
    _linkController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Lūdzu aizpildi lauku: $fieldName';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Lūdzu ievadi e-pastu';
    }
    final email = value.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Lūdzu ievadi korektu e-pastu';
    }
    return null;
  }

  String? _urlValidatorOptional(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) {
      return 'Ievadi korektu saiti';
    }
    return null;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_consentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lūdzu apstiprini piekrišanu datu iesniegšanai'),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
final response = await http.post(
  Uri.parse(_formUrl),
  headers: const {
    'Content-Type': 'application/x-www-form-urlencoded',
  },
  body: {
    _titleEntry: _titleController.text.trim(),
    _descriptionEntry: _mainTextController.text.trim(),
    _linkEntry: _linkController.text.trim(),
    _nameEntry: _nameController.text.trim(),
    _emailEntry: _emailController.text.trim(),
  },
);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 302) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informācija veiksmīgi nosūtīta administratoram'),
          ),
        );

        _formKey.currentState?.reset();
        _titleController.clear();
        _mainTextController.clear();
        _linkController.clear();
        _nameController.clear();
        _emailController.clear();

        setState(() {
          _consentChecked = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Neizdevās nosūtīt informāciju. Kļūda: ${response.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nosūtīšana neizdevās: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      alignLabelWithHint: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pievienot objektu'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Iesniedz jaunu kultūrvēsturisko objektu',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aizpildi formu, un informācija tiks nosūtīta administratoram pārskatīšanai.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: _inputDecoration('Objekta nosaukums *'),
                validator: (value) =>
                    _requiredValidator(value, 'Objekta nosaukums'),
              ),
              const SizedBox(height: 12),
TextFormField(
  controller: _mainTextController,
  decoration: _inputDecoration('Pilnais apraksts *'),
  minLines: 4,
  maxLines: null,
  keyboardType: TextInputType.multiline,
  textInputAction: TextInputAction.newline,
  validator: (value) =>
      _requiredValidator(value, 'Pilnais apraksts'),
),
              const SizedBox(height: 12),
              TextFormField(
                controller: _linkController,
                decoration: _inputDecoration('Saite uz avotu'),
                validator: _urlValidatorOptional,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration('Tavs vārds *'),
                validator: (value) => _requiredValidator(value, 'Tavs vārds'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: _inputDecoration('Tavs e-pasts *'),
                keyboardType: TextInputType.emailAddress,
                validator: _emailValidator,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consentChecked,
                onChanged: (value) {
                  setState(() {
                    _consentChecked = value ?? false;
                  });
                },
                title: const Text(
                  'Es piekrītu, ka iesniegtā informācija var tikt pārskatīta un publicēta lietotnē.',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _sending ? null : _submitForm,
                icon: _sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Nosūta...' : 'Nosūtīt'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '* Obligātie lauki',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}