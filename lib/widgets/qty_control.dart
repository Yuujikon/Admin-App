import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A robust quantity control widget with step buttons (-5, -1, +1, +5)
/// and a direct numeric text input. Enforces minimum quantity of 1
/// and maximum quantity based on stock.
class QtyControl extends StatefulWidget {
  final int qty;
  final int? max;
  final ValueChanged<int> onChanged;

  const QtyControl({
    super.key,
    required this.qty,
    this.max,
    required this.onChanged,
  });

  @override
  State<QtyControl> createState() => _QtyControlState();
}

class _QtyControlState extends State<QtyControl> {
  late TextEditingController _ctrl;
  late FocusNode _focusNode;

  int get _maxVal => (widget.max != null && widget.max! >= 1) ? widget.max! : 9999;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.qty}');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    } else {
      _commit();
    }
  }

  @override
  void didUpdateWidget(QtyControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && (oldWidget.qty != widget.qty || oldWidget.max != widget.max)) {
      final parsed = int.tryParse(_ctrl.text);
      if (parsed != widget.qty) {
        _ctrl.text = '${widget.qty}';
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_ctrl.text);
    final clamped = (parsed ?? widget.qty).clamp(1, _maxVal);
    _ctrl.text = '$clamped';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    if (clamped != widget.qty) {
      widget.onChanged(clamped);
    }
  }

  void _onTextChanged(String val) {
    if (val.isEmpty) return;
    final parsed = int.tryParse(val);
    if (parsed != null) {
      if (parsed > _maxVal) {
        _ctrl.text = '$_maxVal';
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
        widget.onChanged(_maxVal);
      } else if (parsed >= 1) {
        if (parsed != widget.qty) {
          widget.onChanged(parsed);
        }
      }
    }
  }

  void _adjust(int delta) {
    final target = (widget.qty + delta).clamp(1, _maxVal);
    _ctrl.text = '$target';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    if (target != widget.qty) {
      widget.onChanged(target);
    }
  }

  Widget _buildStepButton(String label, int delta) {
    final bool isDisabled = (delta > 0 && widget.qty >= _maxVal) ||
                            (delta < 0 && widget.qty <= 1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => _adjust(delta),
        borderRadius: BorderRadius.circular(15),
        child: Opacity(
          opacity: isDisabled ? 0.3 : 1.0,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStepButton('-5', -5),
        const SizedBox(width: 4),
        _buildStepButton('−', -1),
        const SizedBox(width: 4),
        SizedBox(
          width: 50,
          height: 36,
          child: TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: _onTextChanged,
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
            onTap: () {
              _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(50),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            ),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 4),
        _buildStepButton('+', 1),
        const SizedBox(width: 4),
        _buildStepButton('+5', 5),
      ],
    );
  }
}
