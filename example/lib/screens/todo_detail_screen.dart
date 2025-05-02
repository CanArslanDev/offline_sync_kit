import 'package:flutter/material.dart';
import 'package:offline_sync_kit/offline_sync_kit.dart';
import '../models/todo.dart';

class TodoDetailScreen extends StatefulWidget {
  final Todo todo;

  const TodoDetailScreen({super.key, required this.todo});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late bool _isCompleted;
  late int _priority;
  late Todo _currentTodo;
  bool _useDeltaSync = true; // Delta sync enabled by default

  // Sync strategy selection for this specific todo
  SaveStrategy _saveStrategy = SaveStrategy.optimisticSave;
  FetchStrategy _fetchStrategy = FetchStrategy.backgroundSync;
  DeleteStrategy _deleteStrategy = DeleteStrategy.optimisticDelete;

  @override
  void initState() {
    super.initState();
    _currentTodo = widget.todo;
    _titleController = TextEditingController(text: _currentTodo.title);
    _descriptionController = TextEditingController(
      text: _currentTodo.description,
    );
    _isCompleted = _currentTodo.isCompleted;
    _priority = _currentTodo.priority;

    // Initialize with any existing strategies from the model
    _saveStrategy = _currentTodo.saveStrategy ?? SaveStrategy.optimisticSave;
    _fetchStrategy = _currentTodo.fetchStrategy ?? FetchStrategy.backgroundSync;
    _deleteStrategy =
        _currentTodo.deleteStrategy ?? DeleteStrategy.optimisticDelete;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveTodo() async {
    try {
      if (_useDeltaSync) {
        // Update only changed fields using delta sync
        Todo updatedTodo = _currentTodo;

        // Only update fields that have changed
        if (_titleController.text != _currentTodo.title) {
          updatedTodo = updatedTodo.updateTitle(_titleController.text);
        }

        if (_descriptionController.text != _currentTodo.description) {
          updatedTodo = updatedTodo.updateDescription(
            _descriptionController.text,
          );
        }

        if (_isCompleted != _currentTodo.isCompleted) {
          updatedTodo = updatedTodo.updateCompletionStatus(_isCompleted);
        }

        if (_priority != _currentTodo.priority) {
          updatedTodo = updatedTodo.updatePriority(_priority);
        }

        // Apply the selected sync strategies to this todo
        updatedTodo = updatedTodo.withCustomSyncStrategies(
          saveStrategy: _saveStrategy,
          fetchStrategy: _fetchStrategy,
          deleteStrategy: _deleteStrategy,
        );

        if (updatedTodo.hasChanges) {
          // Save only changed fields
          await OfflineSyncManager.instance.updateModel<Todo>(updatedTodo);

          // Sync using delta sync
          await OfflineSyncManager.instance.syncItemDelta<Todo>(updatedTodo);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Changed fields saved (Delta)')),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No fields changed')));
        }
      } else {
        // Update the entire model - standard method
        final updatedTodo = _currentTodo.copyWith(
          title: _titleController.text,
          description: _descriptionController.text,
          isCompleted: _isCompleted,
          priority: _priority,
          updatedAt: DateTime.now(),
          isSynced: false,
          // Apply the selected sync strategies
          saveStrategy: _saveStrategy,
          fetchStrategy: _fetchStrategy,
          deleteStrategy: _deleteStrategy,
        );

        await OfflineSyncManager.instance.updateModel<Todo>(updatedTodo);

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Todo saved')));
      }

      // Pull latest data from server - using the model's fetch strategy
      await OfflineSyncManager.instance.pullFromServer<Todo>('todo');

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating todo: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteTodo() async {
    try {
      // Create a copy with the selected delete strategy
      final todoToDelete = _currentTodo.withCustomSyncStrategies(
        deleteStrategy: _deleteStrategy,
      );

      // Delete using OfflineSyncManager's deleteModel method instead
      await OfflineSyncManager.instance
          .deleteModel<Todo>(todoToDelete.id, todoToDelete.modelType);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error deleting todo: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Example of finding a specific Todo using Query
  // This method is added to demonstrate usage
  Future<void> _loadTodoWithQuery() async {
    try {
      // Method 1: Direct ID lookup using standard API
      final todoFromStandardApi = await OfflineSyncManager.instance
          .getModel<Todo>(_currentTodo.id, 'todo');

      if (todoFromStandardApi != null) {
        debugPrint(
            'Found todo using standard API: ${todoFromStandardApi.title}');
      }

      // Method 2: Using the Query API (much more powerful)
      // Create Query for ID lookup
      final query = Query.exact('id', _currentTodo.id);

      // Use the new Query-based API
      final results =
          await OfflineSyncManager.instance.getModelsWithQuery<Todo>(
        'todo',
        query: query,
      );

      final todoFromQuery = results.isNotEmpty ? results.first : null;

      if (todoFromQuery != null) {
        setState(() {
          _currentTodo = todoFromQuery;
          _titleController.text = todoFromQuery.title;
          _descriptionController.text = todoFromQuery.description;
          _isCompleted = todoFromQuery.isCompleted;
          _priority = todoFromQuery.priority;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Todo loaded with Query API')),
        );
      }
    } catch (e) {
      debugPrint('Error loading todo with query: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Load with Query',
            onPressed: _loadTodoWithQuery,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _showDeleteConfirmation(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Status: '),
                  Switch(
                    value: _isCompleted,
                    onChanged: (value) {
                      setState(() {
                        _isCompleted = value;
                      });
                    },
                  ),
                  Text(_isCompleted ? 'Completed' : 'Pending'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Priority: '),
                  Slider(
                    value: _priority.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: _priority.toString(),
                    onChanged: (value) {
                      setState(() {
                        _priority = value.toInt();
                      });
                    },
                  ),
                  Text(_priority.toString()),
                ],
              ),
              const SizedBox(height: 16),
              _buildSyncOptions(),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Delta Synchronization'),
                subtitle: const Text('Only send changed fields (faster)'),
                value: _useDeltaSync,
                onChanged: (value) {
                  setState(() {
                    _useDeltaSync = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildSyncStatus(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveTodo,
        tooltip: 'Save',
        child: const Icon(Icons.save),
      ),
    );
  }

  Widget _buildSyncOptions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Model-Level Sync Strategies',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // Save Strategy Selection
            const Text('Save Strategy:'),
            DropdownButton<SaveStrategy>(
              value: _saveStrategy,
              isExpanded: true,
              onChanged: (SaveStrategy? newValue) {
                if (newValue != null) {
                  setState(() {
                    _saveStrategy = newValue;
                  });
                }
              },
              items: SaveStrategy.values.map((SaveStrategy strategy) {
                return DropdownMenuItem<SaveStrategy>(
                  value: strategy,
                  child: Text(_getSaveStrategyName(strategy)),
                );
              }).toList(),
            ),

            const SizedBox(height: 8),

            // Fetch Strategy Selection
            const Text('Fetch Strategy:'),
            DropdownButton<FetchStrategy>(
              value: _fetchStrategy,
              isExpanded: true,
              onChanged: (FetchStrategy? newValue) {
                if (newValue != null) {
                  setState(() {
                    _fetchStrategy = newValue;
                  });
                }
              },
              items: FetchStrategy.values.map((FetchStrategy strategy) {
                return DropdownMenuItem<FetchStrategy>(
                  value: strategy,
                  child: Text(_getFetchStrategyName(strategy)),
                );
              }).toList(),
            ),

            const SizedBox(height: 8),

            // Delete Strategy Selection
            const Text('Delete Strategy:'),
            DropdownButton<DeleteStrategy>(
              value: _deleteStrategy,
              isExpanded: true,
              onChanged: (DeleteStrategy? newValue) {
                if (newValue != null) {
                  setState(() {
                    _deleteStrategy = newValue;
                  });
                }
              },
              items: DeleteStrategy.values.map((DeleteStrategy strategy) {
                return DropdownMenuItem<DeleteStrategy>(
                  value: strategy,
                  child: Text(_getDeleteStrategyName(strategy)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _getSaveStrategyName(SaveStrategy strategy) {
    switch (strategy) {
      case SaveStrategy.optimisticSave:
        return 'Optimistic Save (Local First)';
      case SaveStrategy.waitForRemote:
        return 'Wait For Remote (Server First)';
    }
  }

  String _getFetchStrategyName(FetchStrategy strategy) {
    switch (strategy) {
      case FetchStrategy.backgroundSync:
        return 'Background Sync';
      case FetchStrategy.remoteFirst:
        return 'Remote First';
      case FetchStrategy.localWithRemoteFallback:
        return 'Local with Remote Fallback';
      case FetchStrategy.localOnly:
        return 'Local Only';
    }
  }

  String _getDeleteStrategyName(DeleteStrategy strategy) {
    switch (strategy) {
      case DeleteStrategy.optimisticDelete:
        return 'Optimistic Delete (Local First)';
      case DeleteStrategy.waitForRemote:
        return 'Wait For Remote (Server First)';
    }
  }

  Widget _buildSyncStatus() {
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synchronization Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _currentTodo.isSynced
                      ? Icons.check_circle
                      : Icons.sync_problem,
                  color: _currentTodo.isSynced ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentTodo.isSynced ? 'Synced' : 'Not Synced',
                  style: textStyle,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Created: ${_formatDate(_currentTodo.createdAt)}',
              style: textStyle,
            ),
            Text(
              'Updated: ${_formatDate(_currentTodo.updatedAt)}',
              style: textStyle,
            ),
            if (_currentTodo.hasChanges)
              Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Changed fields: ${_currentTodo.changedFields.join(", ")}',
                    style: textStyle?.copyWith(color: Colors.blue),
                  ),
                ],
              ),
            if (_currentTodo.syncError.isNotEmpty)
              Text(
                'Error: ${_currentTodo.syncError}',
                style: textStyle?.copyWith(color: Colors.red),
              ),
            if (_currentTodo.syncAttempts > 0)
              Text(
                'Sync attempts: ${_currentTodo.syncAttempts}',
                style: textStyle,
              ),
            if (_currentTodo.saveStrategy != null ||
                _currentTodo.fetchStrategy != null ||
                _currentTodo.deleteStrategy != null)
              const Divider(),
            if (_currentTodo.saveStrategy != null)
              Text(
                'Save Strategy: ${_getSaveStrategyName(_currentTodo.saveStrategy!)}',
                style: textStyle?.copyWith(fontWeight: FontWeight.bold),
              ),
            if (_currentTodo.fetchStrategy != null)
              Text(
                'Fetch Strategy: ${_getFetchStrategyName(_currentTodo.fetchStrategy!)}',
                style: textStyle?.copyWith(fontWeight: FontWeight.bold),
              ),
            if (_currentTodo.deleteStrategy != null)
              Text(
                'Delete Strategy: ${_getDeleteStrategyName(_currentTodo.deleteStrategy!)}',
                style: textStyle?.copyWith(fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Todo'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteTodo();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }
}
