import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QtyControl extends StatefulWidget {
  final int qty;
  final int? max;
  final ValueChanged<int> onChanged;
  const QtyControl({super.key, required this.qty, this.max, required this.onChanged});
  @override State<QtyControl> createState() => _QtyControlState();
}

class _QtyControlState extends State<QtyControl> {
  late TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: '${widget.qty}'); }
  @override void didUpdateWidget(QtyControl old) {
    super.didUpdateWidget(old);
    if (old.qty != widget.qty) _ctrl.text = '${widget.qty}';
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  void _adjust(int delta) {
    final next = (widget.qty + delta).clamp(1, widget.max ?? 9999);
    widget.onChanged(next);
  }

  void _commit() {
    final next = (int.tryParse(_ctrl.text) ?? widget.qty).clamp(1, widget.max ?? 9999);
    widget.onChanged(next);
  }

  Widget _btn(String label, int delta, VoidCallback onTap) {
    final bool disabled = (delta > 0 && widget.max != null && widget.qty >= widget.max!) ||
                          (delta < 0 && widget.qty <= 1);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.3 : 1.0,
        child: Container(width: 28, height: 28,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    _btn('-5', -5, () => _adjust(-5)), const SizedBox(width: 4),
    _btn('−', -1, () => _adjust(-1)), const SizedBox(width: 4),
    SizedBox(width: 34, height: 34,
        child: TextField(controller: _ctrl, textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _commit(), onEditingComplete: _commit,
            decoration: InputDecoration(contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(50),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1))),
                filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerLow),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
    const SizedBox(width: 4), 
    _btn('+', 1, () => _adjust(1)),
    const SizedBox(width: 4), 
    _btn('+5', 5, () => _adjust(5)),
  ]);
}