import 'package:flutter/material.dart';

import '../../core/validation.dart';
import 'settings_model.dart';

const List<String> _compressionPresets = <String>['none'];

String _compressionTitle(String preset) {
  switch (preset) {
    case 'none':
      return '\u0411\u0435\u0437 \u0441\u0436\u0430\u0442\u0438\u044f';
    default:
      return '\u0411\u0435\u0437 \u0441\u0436\u0430\u0442\u0438\u044f';
  }
}

String _compressionDescription(String preset) {
  switch (preset) {
    case 'none':
      return '\u0424\u043e\u0442\u043e \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0442\u0441\u044f \u0432 \u0438\u0441\u0445\u043e\u0434\u043d\u043e\u043c \u043a\u0430\u0447\u0435\u0441\u0442\u0432\u0435.';
    default:
      return '\u0424\u043e\u0442\u043e \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u044f\u044e\u0442\u0441\u044f \u0432 \u0438\u0441\u0445\u043e\u0434\u043d\u043e\u043c \u043a\u0430\u0447\u0435\u0441\u0442\u0432\u0435.';
  }
}

Future<AppSettings?> showSettingsSheet(
  BuildContext context, {
  required AppSettings current,
  Future<void> Function()? onOpenHistory,
}) {
  final limitController = TextEditingController(text: current.limitMb);
  var rememberSenderEmail = current.rememberSenderEmail;
  var rememberRecipientEmail = current.rememberRecipientEmail;
  var rememberPassword = current.rememberPassword;
  var autoClearLogBeforeSend = current.autoClearLogBeforeSend;
  var compressionPreset = current.compressionPreset.trim().toLowerCase();
  if (!_compressionPresets.contains(compressionPreset)) {
    compressionPreset = 'none';
  }
  String? limitError;

  void submit(StateSetter setModalState) {
    final validation = Validation.validateLimitMb(limitController.text);
    if (validation != null) {
      setModalState(() {
        limitError = validation;
      });
      return;
    }
    Navigator.of(context).pop(
      current.copyWith(
        limitMb: limitController.text.trim(),
        compressionPreset: compressionPreset,
        rememberSenderEmail: rememberSenderEmail,
        rememberRecipientEmail: rememberRecipientEmail,
        rememberPassword: rememberPassword,
        autoClearLogBeforeSend: autoClearLogBeforeSend,
      ),
    );
  }

  return showModalBottomSheet<AppSettings>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF3F8FF),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              6,
              16,
              MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF224A95),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionCard(
                    title: '\u0410\u043a\u043a\u0430\u0443\u043d\u0442',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: rememberSenderEmail,
                        title: const Text(
                          '\u0421\u043e\u0445\u0440\u0430\u043d\u044f\u0442\u044c email \u043e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u0435\u043b\u044f',
                        ),
                        subtitle: const Text(
                          '\u0415\u0441\u043b\u0438 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d\u043e, \u043f\u043e\u043b\u0435 \u043e\u0447\u0438\u0449\u0430\u0435\u0442\u0441\u044f \u043f\u043e\u0441\u043b\u0435 \u043e\u0442\u043f\u0440\u0430\u0432\u043a\u0438',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            rememberSenderEmail = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: rememberRecipientEmail,
                        title: const Text(
                          '\u0421\u043e\u0445\u0440\u0430\u043d\u044f\u0442\u044c email \u043f\u043e\u043b\u0443\u0447\u0430\u0442\u0435\u043b\u044f',
                        ),
                        subtitle: const Text(
                          '\u0415\u0441\u043b\u0438 \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d\u043e, \u0430\u0434\u0440\u0435\u0441 \u0445\u0440\u0430\u043d\u0438\u0442\u0441\u044f \u0442\u043e\u043b\u044c\u043a\u043e \u0432 \u0442\u0435\u043a\u0443\u0449\u0435\u0439 \u0441\u0435\u0441\u0441\u0438\u0438',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            rememberRecipientEmail = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: rememberPassword,
                        title: const Text(
                          '\u0421\u043e\u0445\u0440\u0430\u043d\u044f\u0442\u044c \u043f\u0430\u0440\u043e\u043b\u044c \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u044f',
                        ),
                        subtitle: const Text(
                          '\u041f\u0430\u0440\u043e\u043b\u044c \u0445\u0440\u0430\u043d\u0438\u0442\u0441\u044f \u0432 \u0437\u0430\u0449\u0438\u0449\u0435\u043d\u043d\u043e\u043c \u0445\u0440\u0430\u043d\u0438\u043b\u0438\u0449\u0435 \u0443\u0441\u0442\u0440\u043e\u0439\u0441\u0442\u0432\u0430',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            rememberPassword = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: '\u041e\u0442\u043f\u0440\u0430\u0432\u043a\u0430',
                    children: [
                      TextField(
                        controller: limitController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '\u041b\u0438\u043c\u0438\u0442 \u043e\u0434\u043d\u043e\u0433\u043e \u043f\u0438\u0441\u044c\u043c\u0430, \u041c\u0411',
                          hintText: '20',
                          errorText: limitError,
                        ),
                        onChanged: (_) {
                          if (limitError != null) {
                            setModalState(() {
                              limitError = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [10, 20, 25, 50].map((value) {
                          return ActionChip(
                            label: Text('$value \u041c\u0411'),
                            onPressed: () {
                              setModalState(() {
                                limitController.text = '$value';
                                limitError = null;
                              });
                            },
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u043a\u0430\u0447\u0435\u0441\u0442\u0432\u0430',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _compressionPresets.map((preset) {
                          return ChoiceChip(
                            label: Text(_compressionTitle(preset)),
                            selected: compressionPreset == preset,
                            onSelected: (_) {
                              setModalState(() {
                                compressionPreset = preset;
                              });
                            },
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _compressionDescription(compressionPreset),
                        style: const TextStyle(color: Color(0xFF3A5B99)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: '\u0411\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u044c',
                    children: const [
                      Text(
                        '\u0411\u0438\u043e\u043c\u0435\u0442\u0440\u0438\u044e, \u0433\u0440\u0430\u0444\u0438\u0447\u0435\u0441\u043a\u0438\u0439 \u043f\u0430\u0440\u043e\u043b\u044c \u0438 \u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u043a\u0443 \u043f\u0440\u0438 \u0437\u0430\u043f\u0443\u0441\u043a\u0435 \u043c\u043e\u0436\u043d\u043e \u043d\u0430\u0441\u0442\u0440\u043e\u0438\u0442\u044c \u043d\u0430 \u0433\u043b\u0430\u0432\u043d\u043e\u043c \u044d\u043a\u0440\u0430\u043d\u0435 \u0432 \u0440\u0430\u0437\u0434\u0435\u043b\u0435 \u00ab\u0411\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u043e\u0441\u0442\u044c\u00bb.',
                        style: TextStyle(color: Color(0xFF3A5B99)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: '\u0418\u0441\u0442\u043e\u0440\u0438\u044f \u0438 \u043f\u043e\u0432\u0435\u0434\u0435\u043d\u0438\u0435',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: autoClearLogBeforeSend,
                        title: const Text(
                          '\u041e\u0447\u0438\u0449\u0430\u0442\u044c \u043b\u043e\u0433 \u043f\u0435\u0440\u0435\u0434 \u043d\u043e\u0432\u043e\u0439 \u043e\u0442\u043f\u0440\u0430\u0432\u043a\u043e\u0439',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            autoClearLogBeforeSend = value;
                          });
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: const Text(
                          '\u041e\u0442\u043a\u0440\u044b\u0442\u044c \u0438\u0441\u0442\u043e\u0440\u0438\u044e \u043e\u0442\u043f\u0440\u0430\u0432\u043e\u043a',
                        ),
                        subtitle: const Text(
                          '\u041f\u0435\u0440\u0435\u0445\u043e\u0434 \u043a \u043b\u043e\u0433\u0430\u043c \u043d\u0430 \u0433\u043b\u0430\u0432\u043d\u043e\u043c \u044d\u043a\u0440\u0430\u043d\u0435',
                        ),
                        onTap: onOpenHistory == null
                            ? null
                            : () async {
                                Navigator.of(context).pop();
                                await onOpenHistory();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => submit(setModalState),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      '\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(limitController.dispose);
}

Widget _sectionCard({
  required String title,
  required List<Widget> children,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDAE8FF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E4D9A),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}
