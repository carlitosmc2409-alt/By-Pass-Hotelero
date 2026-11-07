import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pantalla de Camuflaje Discreto ("Stealth Mode"):
/// Funciona como una calculadora real de bolsillo sin ningún rastro visual de hoteles o QR.
/// Si el usuario ingresa su PIN discreto (por defecto `2409`) y pulsa `=`, o mantiene pulsado `=`,
/// desbloquea silenciosamente la sesión privada de StayPass.
class StealthCalculatorScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const StealthCalculatorScreen({super.key, required this.onUnlock});

  static const _pinKey = 'staypass_stealth_pin';
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  static void enable() {
    active.value = true;
  }

  static void disable() {
    active.value = false;
  }

  static Future<String> getSavedPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_pinKey) ?? '2409';
    } catch (_) {
      return '2409';
    }
  }

  static Future<void> savePin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinKey, pin);
    } catch (_) {}
  }

  @override
  State<StealthCalculatorScreen> createState() =>
      _StealthCalculatorScreenState();
}

class _StealthCalculatorScreenState extends State<StealthCalculatorScreen> {
  String _display = '0';
  double? _firstOperand;
  String? _operator;
  bool _resetNext = false;
  String _savedPin = '2409';

  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  Future<void> _loadPin() async {
    final p = await StealthCalculatorScreen.getSavedPin();
    if (mounted) setState(() => _savedPin = p);
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'C') {
        _display = '0';
        _firstOperand = null;
        _operator = null;
        _resetNext = false;
        return;
      }

      if (key == '⌫') {
        if (_display.length > 1) {
          _display = _display.substring(0, _display.length - 1);
        } else {
          _display = '0';
        }
        return;
      }

      if (key == '+' || key == '-' || key == '×' || key == '÷') {
        _firstOperand = double.tryParse(_display) ?? 0;
        _operator = key;
        _resetNext = true;
        return;
      }

      if (key == '=') {
        // Desbloqueo silencioso si el número en pantalla coincide con el PIN privado
        if (_operator == null && _display == _savedPin) {
          widget.onUnlock();
          return;
        }
        if (_firstOperand != null && _operator != null) {
          final second = double.tryParse(_display) ?? 0;
          double res = second;
          if (_operator == '+') res = _firstOperand! + second;
          if (_operator == '-') res = _firstOperand! - second;
          if (_operator == '×') res = _firstOperand! * second;
          if (_operator == '÷') res = second == 0 ? 0 : _firstOperand! / second;
          _display = res == res.roundToDouble()
              ? res.toInt().toString()
              : res.toStringAsFixed(2);
          _firstOperand = null;
          _operator = null;
          _resetNext = true;
        }
        return;
      }

      if (_resetNext || _display == '0') {
        _display = key == '.' ? '0.' : key;
        _resetNext = false;
      } else {
        if (key == '.' && _display.contains('.')) return;
        if (_display.length < 12) {
          _display += key;
        }
      }
    });
  }

  Future<void> _openPinConfigDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14161D),
        title: const Text('Desbloquear vista privada'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Ingresa tu PIN (por defecto 2409)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim() == _savedPin) {
                Navigator.of(ctx).pop();
                widget.onUnlock();
              }
            },
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['C', '⌫', '÷', '×'],
      ['7', '8', '9', '-'],
      ['4', '5', '6', '+'],
      ['1', '2', '3', '='],
      ['0', '.', '', ''],
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0B0F),
        title: const Text(
          'Calculadora Rápida',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            tooltip: 'Opciones',
            onPressed: _openPinConfigDialog,
            icon: const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.white38),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12141C),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_operator != null && _firstOperand != null)
                          Text(
                            '${_firstOperand!} $_operator',
                            style: const TextStyle(color: Colors.white38, fontSize: 15),
                          ),
                        Text(
                          _display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tip: escribe tu PIN y pulsa "=" para regresar',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white24),
                  ),
                  const SizedBox(height: 14),
                  ...keys.take(4).map((row) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: row.map((k) {
                          final isOp = ['÷', '×', '-', '+', '='].contains(k);
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: SizedBox(
                                height: 62,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: k == '='
                                        ? const Color(0xFF334155)
                                        : isOp
                                            ? const Color(0xFF1E2433)
                                            : const Color(0xFF151822),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () => _onKey(k),
                                  onLongPress: k == '=' ? widget.onUnlock : null,
                                  child: Text(
                                    k,
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: SizedBox(
                            height: 58,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF151822),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => _onKey('0'),
                              child: const Text('0', style: TextStyle(fontSize: 20)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: SizedBox(
                            height: 58,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF151822),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => _onKey('.'),
                              child: const Text('.', style: TextStyle(fontSize: 22)),
                            ),
                          ),
                        ),
                      ),
                    ],
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
