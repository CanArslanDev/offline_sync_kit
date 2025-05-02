import 'dart:async';
import 'package:flutter/material.dart';
import 'package:offline_sync_kit/offline_sync_kit.dart';
import '../models/todo.dart';
import '../models/encryption_manager.dart';
import 'todo_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Todo> _todos = [];
  SyncStatus _syncStatus = SyncStatus();
  bool _isLoading = true;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ConflictResolutionStrategy _conflictStrategy =
      ConflictResolutionStrategy.lastUpdateWins;
  bool _isEncryptionEnabled = true;
  late final EncryptionManager _encryptionManager;

  @override
  void initState() {
    super.initState();
    _encryptionManager = EncryptionManager();
    _setupSyncStatusListener();
    _setupEncryptionListener();
    _loadTodos();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setupSyncStatusListener() {
    OfflineSyncManager.instance.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _syncStatus = status;
        });
      }
    });
  }

  void _setupEncryptionListener() {
    _encryptionManager.encryptionStatusStream.listen((isEnabled) {
      if (mounted) {
        setState(() {
          _isEncryptionEnabled = isEnabled;
        });
      }
    });
  }

  Future<void> _loadTodos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Use the Query API for more powerful data retrieval
      if (_searchQuery.isEmpty) {
        // When no search query, we can get all todos organized by completion state
        // First get incomplete todos with high priority first
        final notCompletedQuery = Query(
          where: [WhereCondition.exact('isCompleted', false)],
          orderBy: 'priority',
          descending: true, // High priority first
        );

        final notCompletedTodos = await OfflineSyncManager.instance
            .getModelsWithQuery<Todo>('todo', query: notCompletedQuery);

        // Then get completed todos sorted by update time
        final completedQuery = Query(
          where: [WhereCondition.exact('isCompleted', true)],
          orderBy: 'updatedAt',
          descending: true, // Most recently completed first
        );

        final completedTodos = await OfflineSyncManager.instance
            .getModelsWithQuery<Todo>('todo', query: completedQuery);

        setState(() {
          _todos.clear();
          _todos.addAll(notCompletedTodos);
          _todos.addAll(completedTodos);
          _isLoading = false;
        });
      } else {
        // When searching, we need to search in both title and description
        // First search by title
        final titleQuery = Query(
          where: [WhereCondition.contains('title', _searchQuery)],
          orderBy: 'priority',
          descending: true,
        );

        final titleResults = await OfflineSyncManager.instance
            .getModelsWithQuery<Todo>('todo', query: titleQuery);

        // Then search by description
        final descriptionQuery = Query(
          where: [WhereCondition.contains('description', _searchQuery)],
          orderBy: 'priority',
          descending: true,
        );

        final descriptionResults = await OfflineSyncManager.instance
            .getModelsWithQuery<Todo>('todo', query: descriptionQuery);

        // Combine results without duplicates
        final Set<Todo> uniqueTodos = <Todo>{};
        uniqueTodos.addAll(titleResults);
        uniqueTodos.addAll(descriptionResults);

        setState(() {
          _todos.clear();
          _todos.addAll(uniqueTodos);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading todos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _syncTodos() async {
    try {
      setState(() {
        _errorMessage = '';
      });

      // Synchronize all Todo models
      final result = await OfflineSyncManager.instance.syncByModelType('todo');

      if (!mounted) return;

      if (result.status == SyncResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync successful! ${result.processedItems} items synchronized.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result.status == SyncResultStatus.partial) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Partial sync: ${result.processedItems} successful, ${result.failedItems} failed',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (result.status == SyncResultStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${result.errorMessages.join(", ")}'),
            backgroundColor: Colors.red,
          ),
        );
      }

      await _loadTodos();
    } catch (e) {
      setState(() {
        _errorMessage = 'Sync error: $e';
      });
    }
  }

  Future<void> _pullFromServer() async {
    try {
      setState(() {
        _errorMessage = '';
      });

      // Pull latest data from server
      final result = await OfflineSyncManager.instance.pullFromServer<Todo>(
        'todo',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.processedItems} todos pulled from server'),
          backgroundColor: Colors.blue,
        ),
      );

      await _loadTodos();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error pulling from server: $e';
      });
    }
  }

  Future<void> _addTodo() async {
    final titleController = TextEditingController();

    return showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Add New Todo'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(labelText: 'Todo Title'),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Add'),
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  final newTodo = Todo(
                    title: titleController.text,
                    description: '',
                    isCompleted: false,
                    priority: 3,
                  );

                  try {
                    await OfflineSyncManager.instance.saveModel<Todo>(newTodo);

                    if (!mounted) return;
                    Navigator.of(context).pop();

                    await _loadTodos();

                    // Sync the new todo immediately
                    await OfflineSyncManager.instance.syncItem<Todo>(newTodo);
                  } catch (e) {
                    debugPrint('Error adding todo: $e');
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding todo: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _navigateToDetail(Todo todo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TodoDetailScreen(todo: todo)),
    );

    // Reload todos when returning from detail screen
    _syncTodos();
    _loadTodos();
  }

  void _showConflictStrategyDialog() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Settings'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Conflict Resolution Strategy',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<ConflictResolutionStrategy>(
                    title: const Text('Server Wins'),
                    subtitle: const Text(
                      'Server version always takes precedence',
                    ),
                    value: ConflictResolutionStrategy.serverWins,
                    groupValue: _conflictStrategy,
                    onChanged: (value) {
                      setState(() {
                        _conflictStrategy = value!;
                      });
                    },
                  ),
                  RadioListTile<ConflictResolutionStrategy>(
                    title: const Text('Client Wins'),
                    subtitle: const Text('Local changes take precedence'),
                    value: ConflictResolutionStrategy.clientWins,
                    groupValue: _conflictStrategy,
                    onChanged: (value) {
                      setState(() {
                        _conflictStrategy = value!;
                      });
                    },
                  ),
                  RadioListTile<ConflictResolutionStrategy>(
                    title: const Text('Last Update Wins'),
                    subtitle: const Text(
                      'Most recently updated version takes precedence',
                    ),
                    value: ConflictResolutionStrategy.lastUpdateWins,
                    groupValue: _conflictStrategy,
                    onChanged: (value) {
                      setState(() {
                        _conflictStrategy = value!;
                      });
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Security Settings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SwitchListTile(
                    title: const Text('Data Encryption'),
                    subtitle: const Text(
                      'Encrypt data before sending to server',
                    ),
                    value: _isEncryptionEnabled,
                    onChanged: (value) {
                      setState(() {
                        _isEncryptionEnabled = value;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                await _updateSettings();
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showAnalyticsModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Synchronization Statistics',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _buildAnalyticsItem(
                'Last sync',
                _formatDate(_syncStatus.lastSyncTime),
              ),
              _buildAnalyticsItem(
                'Pending changes',
                _syncStatus.pendingChanges.toString(),
              ),
              _buildAnalyticsItem(
                'Sync status',
                _syncStatus.isSyncing ? 'Active' : 'Ready',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Sync Kit Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Synchronization Statistics',
            onPressed: _showAnalyticsModal,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Conflict Strategy',
            onPressed: _showConflictStrategyDialog,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Synchronize',
            onPressed: _syncTodos,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Pull from Server',
            onPressed: _pullFromServer,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSyncStatusBar(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Todos',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      _searchQuery = _searchController.text;
                      _loadTodos();
                    });
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                setState(() {
                  _searchQuery = value;
                  _loadTodos();
                });
              },
            ),
          ),
          Expanded(child: _buildTodoList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTodo,
        tooltip: 'Add Todo',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSyncStatusBar() {
    IconData iconData;
    Color color;
    String statusText;

    if (!_syncStatus.isConnected) {
      iconData = Icons.cloud_off;
      color = Colors.red;
      statusText = 'Offline';
    } else if (_syncStatus.isSyncing) {
      iconData = Icons.sync;
      color = Colors.blue;
      statusText = 'Syncing...';
    } else if (_syncStatus.pendingChanges > 0) {
      iconData = Icons.sync_problem;
      color = Colors.orange;
      statusText = '${_syncStatus.pendingChanges} pending changes';
    } else {
      iconData = Icons.cloud_done;
      color = Colors.green;
      statusText = 'Synced';
    }

    return Container(
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(iconData, color: color),
          const SizedBox(width: 8),
          Text(statusText, style: TextStyle(color: color)),
          const Spacer(),
          Text(
            'Conflict strategy: ${_getStrategyName(_conflictStrategy)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _getStrategyName(ConflictResolutionStrategy strategy) {
    switch (strategy) {
      case ConflictResolutionStrategy.serverWins:
        return 'Server Wins';
      case ConflictResolutionStrategy.clientWins:
        return 'Client Wins';
      case ConflictResolutionStrategy.lastUpdateWins:
        return 'Last Update Wins';
      case ConflictResolutionStrategy.custom:
        return 'Custom';
    }
  }

  Widget _buildTodoList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTodos,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_todos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.list, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No todos found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addTodo,
              child: const Text('Add First Todo'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        final todo = _todos[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            leading: Icon(
              todo.isCompleted ? Icons.check_circle : Icons.circle_outlined,
              color: todo.isCompleted ? Colors.green : Colors.grey,
            ),
            title: Text(
              todo.title,
              style: TextStyle(
                decoration: todo.isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (todo.description.isNotEmpty)
                  Text(
                    todo.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Row(
                  children: [
                    Icon(
                      todo.isSynced ? Icons.cloud_done : Icons.cloud_upload,
                      size: 14,
                      color: todo.isSynced ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      todo.isSynced ? 'Synced' : 'Not synced',
                      style: TextStyle(
                        fontSize: 12,
                        color: todo.isSynced ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (todo.hasChanges)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.edit, size: 14, color: Colors.blue),
                      ),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(todo.priority),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'P${todo.priority}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _navigateToDetail(todo),
                ),
              ],
            ),
            onTap: () => _navigateToDetail(todo),
          ),
        );
      },
    );
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.blue;
      case 4:
        return Colors.green;
      case 5:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }

  Future<void> _loadCurrentSettings() async {
    // Get the current settings from EncryptionManager
    try {
      setState(() {
        _isEncryptionEnabled = _encryptionManager.isEncryptionEnabled;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _updateSettings() async {
    try {
      // Then handle encryption settings
      if (_isEncryptionEnabled != _encryptionManager.isEncryptionEnabled) {
        if (_isEncryptionEnabled) {
          // User is enabling encryption, need a key
          final encryptionKey = await _showEncryptionKeyDialog();
          if (encryptionKey != null && encryptionKey.isNotEmpty) {
            // Enable encryption with the provided key
            await _encryptionManager.enableEncryption(encryptionKey);

            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Encryption enabled')));
          } else {
            // If no key provided, revert back to previous state
            setState(() {
              _isEncryptionEnabled = _encryptionManager.isEncryptionEnabled;
            });
          }
        } else {
          // User is disabling encryption
          await _encryptionManager.disableEncryption();

          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Encryption disabled')));
        }
      }
    } catch (e) {
      debugPrint('Error updating settings: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating settings: $e')));

      // Revert back to the actual state in case of error
      setState(() {
        _isEncryptionEnabled = _encryptionManager.isEncryptionEnabled;
      });
    }
  }

  Future<String?> _showEncryptionKeyDialog() async {
    final keyController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Encryption Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a secure encryption key:'),
              const SizedBox(height: 8),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  hintText: 'Encryption key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Warning: Changing encryption settings will require re-syncing all data.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(keyController.text),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}
