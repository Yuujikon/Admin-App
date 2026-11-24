import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/audit_log.dart';
import '../services/audit_log_service.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AuditLogService _auditLogService = AuditLogService();
  String _selectedModule = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _modules = [
    'All',
    'Auth & Security',
    'Roles & Accounts',
    'Inventory',
    'POS',
    'Shifts & Cash',
    'Pre-Orders',
    'Refunds',
    'Suppliers',
    'Complaints & Restrictions',
    'Reports'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getModuleColor(String module) {
    switch (module.toLowerCase()) {
      case 'auth & security':
      case 'roles & accounts':
        return Colors.blue;
      case 'pos':
      case 'shifts & cash':
        return Colors.green;
      case 'inventory':
      case 'suppliers':
        return Colors.orange;
      case 'pre-orders':
      case 'refunds':
        return Colors.teal;
      case 'complaints & restrictions':
        return Colors.red;
      case 'reports':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  void _showLogDetails(AuditLog log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audit Log Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(
                  'Timestamp',
                  DateFormat('MMM d, y h:mm:ss a')
                      .format(log.timestamp.toDate())),
              _detailRow('Action', log.action),
              _detailRow('Module', log.module),
              _detailRow('Target', log.targetName),
              _detailRow('Target ID', log.targetId),
              _detailRow('Summary', log.summary),
              _detailRow('Actor', '${log.actorName ?? ''} (${log.actorEmail})'),
              _detailRow('Role', log.actorRole.toUpperCase()),
              if (log.afterData != null)
                _buildItemizedBreakdown(log.afterData!),
              if (log.beforeData != null || log.afterData != null) ...[
                const Divider(height: 32),
                if (log.beforeData != null) ...[
                  const Text('Before:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.red.withValues(alpha: 0.1),
                    child: Text(log.beforeData.toString()),
                  ),
                  const SizedBox(height: 8),
                ],
                if (log.afterData != null) ...[
                  const Text('Raw Snapshot Data:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.green.withValues(alpha: 0.1),
                    child: Text(log.afterData.toString()),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Widget _buildItemizedBreakdown(Map<String, dynamic> afterData) {
    List<dynamic> received =
        List.from(afterData['itemsReceivedSummary'] as List<dynamic>? ?? []);
    List<dynamic> missing =
        List.from(afterData['itemsMissingSummary'] as List<dynamic>? ?? []);
    List<dynamic> ordered =
        List.from(afterData['itemsOrderedSummary'] as List<dynamic>? ?? []);

    // Fallback: if updatedItems is present instead
    if (received.isEmpty &&
        missing.isEmpty &&
        afterData['updatedItems'] != null) {
      final List<dynamic> updatedItems =
          afterData['updatedItems'] as List<dynamic>;
      for (final raw in updatedItems) {
        if (raw is Map) {
          final int rec = (raw['receivedQty'] as num? ?? 0).toInt();
          final int ord = (raw['orderedQty'] as num? ?? 0).toInt();
          final int rej = (raw['rejectedQty'] as num? ?? 0).toInt();
          final int rem = (raw['remainingQty'] as num? ?? (ord - rec)).toInt();
          final String name = raw['productName'] ?? 'Item';
          final String sku = raw['sku'] ?? '';

          if (rec > 0) {
            received.add({
              'productName': name,
              'sku': sku,
              'receivedQty': rec,
              'actualUnitCost': raw['actualUnitCost'] ?? raw['unitCost'] ?? 0,
            });
          }
          if (rem > 0 || rej > 0) {
            missing.add({
              'productName': name,
              'sku': sku,
              'orderedQty': ord,
              'receivedQty': rec,
              'missingQty': rem + rej,
              'rejectionReason': raw['rejectionReason'] ?? 'Unfulfilled',
            });
          }
        }
      }
    }

    if (received.isEmpty && missing.isEmpty && ordered.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'ITEMIZED AUDIT LOG BREAKDOWN',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        const SizedBox(height: 8),

        // 1. Items Received Box
        if (received.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 16, color: Colors.green.shade800),
                    const SizedBox(width: 6),
                    Text(
                      'Items Received & Accepted (${received.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.green.shade900),
                    ),
                  ],
                ),
                const Divider(height: 12),
                ...received.map((item) {
                  final name = item['productName'] ?? 'Item';
                  final qty = item['receivedQty'] ?? 0;
                  final cost = item['actualUnitCost'] ?? item['unitCost'] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text('• $name',
                                style: const TextStyle(fontSize: 12))),
                        Text('$qty units @ ₱${cost.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 2. Items Missing / Shortage Box
        if (missing.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.orange.shade900),
                    const SizedBox(width: 6),
                    Text(
                      'Items Missing / Shortage (${missing.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.orange.shade900),
                    ),
                  ],
                ),
                const Divider(height: 12),
                ...missing.map((item) {
                  final name = item['productName'] ?? 'Item';
                  final missingQty = item['missingQty'] ??
                      (item['orderedQty'] - item['receivedQty']);
                  final reason = item['rejectionReason'] ?? 'Unfulfilled';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text('• $name',
                                style: const TextStyle(fontSize: 12))),
                        Text('Missing: $missingQty units ($reason)',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 3. Items Ordered Box (For PO Creation)
        if (ordered.isNotEmpty && received.isEmpty && missing.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shopping_cart_outlined,
                        size: 16, color: Colors.blue.shade800),
                    const SizedBox(width: 6),
                    Text(
                      'Items Ordered (${ordered.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.blue.shade900),
                    ),
                  ],
                ),
                const Divider(height: 12),
                ...ordered.map((item) {
                  final name = item['productName'] ?? 'Item';
                  final qty = item['orderedQty'] ?? 0;
                  final cost = item['unitCost'] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text('• $name',
                                style: const TextStyle(fontSize: 12))),
                        Text('$qty units @ ₱${cost.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Audit Logs'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search logs...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedModule,
                    decoration: const InputDecoration(
                      labelText: 'Module Filter',
                      border: OutlineInputBorder(),
                    ),
                    items: _modules
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedModule = val);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AuditLog>>(
              stream: _auditLogService.getAuditLogs(limit: 100),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading logs: ${snapshot.error}'));
                }
                final logs = snapshot.data ?? [];

                final filteredLogs = logs.where((log) {
                  final matchModule = _selectedModule == 'All' ||
                      log.module.toLowerCase() == _selectedModule.toLowerCase();
                  final matchSearch = _searchQuery.isEmpty ||
                      log.summary.toLowerCase().contains(_searchQuery) ||
                      log.action.toLowerCase().contains(_searchQuery) ||
                      log.targetName.toLowerCase().contains(_searchQuery) ||
                      log.actorEmail.toLowerCase().contains(_searchQuery);
                  return matchModule && matchSearch;
                }).toList();

                if (filteredLogs.isEmpty) {
                  return const Center(child: Text('No audit logs found.'));
                }

                return ListView.builder(
                  itemCount: filteredLogs.length,
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    final moduleColor = _getModuleColor(log.module);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: moduleColor.withValues(alpha: 0.2),
                          child: Icon(Icons.history, color: moduleColor),
                        ),
                        title: Text(log.summary,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: moduleColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    log.action,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM d, h:mm a')
                                      .format(log.timestamp.toDate()),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                                'By: ${log.actorName ?? log.actorEmail} (${log.actorRole})',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        isThreeLine: true,
                        onTap: () => _showLogDetails(log),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
