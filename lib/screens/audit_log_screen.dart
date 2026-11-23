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
    switch (module) {
      case 'Auth & Security':
      case 'Roles & Accounts':
        return Colors.blue;
      case 'POS':
      case 'Shifts & Cash':
        return Colors.green;
      case 'Inventory':
      case 'Suppliers':
        return Colors.orange;
      case 'Pre-Orders':
      case 'Refunds':
        return Colors.teal;
      case 'Complaints & Restrictions':
        return Colors.red;
      case 'Reports':
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
              _detailRow('Timestamp', DateFormat('MMM d, y h:mm:ss a').format(log.timestamp.toDate())),
              _detailRow('Action', log.action),
              _detailRow('Module', log.module),
              _detailRow('Target', log.targetName),
              _detailRow('Target ID', log.targetId),
              _detailRow('Summary', log.summary),
              _detailRow('Actor', '${log.actorName ?? ''} (${log.actorEmail})'),
              _detailRow('Role', log.actorRole.toUpperCase()),
              if (log.beforeData != null || log.afterData != null) ...[
                const Divider(height: 32),
                if (log.beforeData != null) ...[
                  const Text('Before:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.red.withValues(alpha: 0.1),
                    child: Text(log.beforeData.toString()),
                  ),
                  const SizedBox(height: 8),
                ],
                if (log.afterData != null) ...[
                  const Text('After:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
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
                    onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _selectedModule,
                    decoration: const InputDecoration(
                      labelText: 'Module Filter',
                      border: OutlineInputBorder(),
                    ),
                    items: _modules.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
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
                  return Center(child: Text('Error loading logs: ${snapshot.error}'));
                }
                final logs = snapshot.data ?? [];
                
                final filteredLogs = logs.where((log) {
                  final matchModule = _selectedModule == 'All' || log.module == _selectedModule;
                  final matchSearch = _searchQuery.isEmpty ||
                      log.summary.toLowerCase().contains(_searchQuery) ||
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
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: moduleColor.withValues(alpha: 0.2),
                          child: Icon(Icons.history, color: moduleColor),
                        ),
                        title: Text(log.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: moduleColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    log.action,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM d, h:mm a').format(log.timestamp.toDate()),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('By: ${log.actorName ?? log.actorEmail} (${log.actorRole})', style: const TextStyle(fontSize: 12)),
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
