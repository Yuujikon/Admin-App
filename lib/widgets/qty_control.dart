import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A robust quantity control widget with step buttons (-5, -1, +1, +5)
/// and a direct numeric text input. Enforces minimum quantity of 1
/// and maximum quantity based on stock.
class QtyControl extends StatefulWidget {
  final int qty;
  final int min;
  final int? max;
  final ValueChanged<int> onChanged;

  const QtyControl({
    super.key,
    required this.qty,
    this.min = 1,
    this.max,
    required this.onChanged,
  });

  @override
  State<QtyControl> createState() => _QtyControlState();
}

class _QtyControlState extends State<QtyControl> {
  late TextEditingController _ctrl;
  late FocusNode _focusNode;

  int get _maxVal =>
      (widget.max != null && widget.max! >= 1) ? widget.max! : 9999;

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
    if (!_focusNode.hasFocus &&
        (oldWidget.qty != widget.qty || oldWidget.max != widget.max)) {
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
    final clamped = (parsed ?? widget.qty).clamp(widget.min, _maxVal);
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
      } else if (parsed >= widget.min) {
        if (parsed != widget.qty) {
          widget.onChanged(parsed);
        }
      }
    }
  }

  void _adjust(int delta) {
    final target = (widget.qty + delta).clamp(widget.min, _maxVal);
    _ctrl.text = '$target';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    if (target != widget.qty) {
      widget.onChanged(target);
    }
  }

  Widget _buildStepButton(String label, int delta) {
    final bool isDisabled = (delta > 0 && widget.qty >= _maxVal) ||
        (delta < 0 && widget.qty <= widget.min);

    final isMajorStep = delta == 5 || delta == -5;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => _adjust(delta),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isDisabled ? 0.35 : 1.0,
          child: Container(
            width: isMajorStep ? 34 : 32,
            height: 32,
            decoration: BoxDecoration(
              color: isMajorStep
                  ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isMajorStep
                    ? colorScheme.primary.withValues(alpha: 0.25)
                    : colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isMajorStep ? 11 : 13,
                fontWeight: FontWeight.w800,
                color:
                    isMajorStep ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildStepButton('-5', -5),
          const SizedBox(width: 3),
          _buildStepButton('−', -1),
          const SizedBox(width: 4),
          SizedBox(
            width: 52,
            height: 34,
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
                _ctrl.selection =
                    TextSelection.collapsed(offset: _ctrl.text.length);
              },
              decoration: InputDecoration(
                contentPadding: EdgeInsets.zero,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: colorScheme.surface,
              ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildStepButton('+', 1),
          const SizedBox(width: 3),
          _buildStepButton('+5', 5),
        ],
      ),
    );
  }
}
